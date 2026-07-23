// TODO: Rewrite completely, fix, it's broken

`include "params.svh"

module gauss (
    input clk,
    input reset,
    input [OUTPUT_WIDTH-1:0] partial_mat,
    input [$clog2(GAUS_UNITS)+1:0] broadcast_to,
    input [$clog2(GAUS_UNITS)+1:0] broadcast_target,
    input broadcast_valid,

    output reg done,
    output reg correct
);

// states
localparam int uninitialized = 0;
localparam int receive = 1;
localparam int select = 2;
localparam int eliminate = 3;
localparam int popcount = 4;
localparam int stall = 5;

reg [$clog2(HEIGHT)-1:0] col_ptr;
reg [$clog2(HEIGHT)-1:0] copy_ptr;

(* ramstyle = "M10K" *) reg [15:0] [(HEIGHT*HEIGHT)/16:0] internal_mat;
reg [HEIGHT-1:0] internal_syndrome;
reg [2:0] state; // receive, select, eliminate, popcount 

reg [$clog2(HEIGHT)-1:0] search_ptr;
reg [$clog2(HEIGHT)-1:0] col_search_ptr;
reg tmp_s_coord;
reg [HEIGHT-1:0] tmp_vect;

reg [$clog2(HEIGHT)-1:0] elim_row_ptr;

reg [$clog2(HEIGHT):0] count_syndrome_ptr;
reg [$clog2(HEIGHT)-1:0] bitcount;
reg [$clog2(BITS_COUNTED_PER_CYCLE)-1:0] temp_bitcount;
reg [BITS_COUNTED_PER_CYCLE-1:0] count_vect;

reg we;
reg [($clog2((HEIGHT*HEIGHT)/16)-1):0] write_ptr;
reg [($clog2((HEIGHT*HEIGHT)/16)-1):0] read_ptr;
reg [15:0] write_buffer;
reg [15:0] read_buffer;

always_ff @(posedge clk) begin
    if (we) begin
        internal_mat[write_ptr] <= write_buffer;
    end
    read_buffer <= internal_mat[read_ptr];
end 

always_comb begin
    temp_bitcount = 0;
    for (int i = 0; i < BITS_COUNTED_PER_CYCLE; i++) begin
        temp_bitcount = temp_bitcount + count_vect[i];
    end
end

always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        we <= 0;
        copy_ptr <= 0;
        col_ptr <= 0;
        correct <= 0;
        state <= 0;
        done <= 1;
    end else begin
        case (state)
            uninitialized : begin
                    read_ptr <= '0;
                    write_ptr <= '0;
                    we <= '0;

                    if (broadcast_valid && broadcast_to == broadcast_target) begin
                        done <= '0;
                        state <= state + 1;
                    end
                end
            receive : begin
                    col_search_ptr <= '0;
                    search_ptr <= '0;
                    for (int i = 0; i < OUTPUT_WIDTH; i++) begin
                        internal_mat[copy_ptr+i][col_ptr] <= partial_mat[i];
                    end
                    if (copy_ptr+OUTPUT_WIDTH != HEIGHT) begin
                        copy_ptr <= copy_ptr + OUTPUT_WIDTH;
                    end else begin
                        copy_ptr <= '0;
                        if (col_ptr == HEIGHT) begin 
                            internal_syndrome <= `SYNDROME;
                            col_ptr <= '0;
                            state <= state + 1;
                            done <= '0;
                        end else col_ptr <= col_ptr + 1;
                    end
                end
            // originally was going to be a tree-based-search, but considering the fact 
            // that we often will see the needed bit early in the search (there's a (1/2)^n 
            // chance we will not find it, where n is how deep we are into the search)
            // it is not necessary to implement something better than the priority encoder
            // so this is done for better LUT usage at the cost of possibly worse timing in
            // rare-ish cases
            select : begin
                    search_ptr <= search_ptr + SEARCH_PER_CYCLE;
                    for (int i = 0; i < SEARCH_PER_CYCLE; i++) begin
                        if (internal_mat[rename_table[i+search_ptr]][col_search_ptr] && free_list[rename_table[i+search_ptr]]) begin 
                            // originally was going to be a rename structure, but would require a tree-based approach and increase 
                            // logic usage too much. Edit: two rename tables can be used for an easy inverse mapping so linear
                            // search can still work
                            free_list[rename_table[i+search_ptr]] <= 1'b0;
                            rename_table[col_search_ptr] <= rename_table[i+search_ptr];
                            rename_table[i+search_ptr] <= rename_table[col_search_ptr];

                            // improve naming convention!!!!
                            internal_syndrome[col_search_ptr] <= internal_syndrome[i+search_ptr];
                            internal_syndrome[i+search_ptr] <= internal_syndrome[col_search_ptr];
                            state <= state + 1;
                            elim_row_ptr <= '0;
                            tmp_s_coord <= internal_syndrome[i+search_ptr];
                            tmp_vect <= internal_mat[rename_table[i+search_ptr]];
                            break;
                        end else if (search_ptr+i == HEIGHT-1) begin
                            state <= '0;
                            done <= '1;
                        end
                    end
                end
            eliminate : begin // ~~note to self: see if REF is faster/better circut complexity (answer is likely yes)~~ do NOT do this
                    for (int i = 0; i < ELIMINATE_PER_CYCLE; i++) begin
                        if (internal_mat[rename_table[elim_row_ptr+i]][col_search_ptr] && // if the bit needs to be flipped
                            (col_search_ptr != elim_row_ptr+i)) begin // and it's not the row we're using for elimination
                                internal_mat[rename_table[elim_row_ptr+i]] <= internal_mat[rename_table[elim_row_ptr+i]] ^ tmp_vect;
                                internal_syndrome[elim_row_ptr+i] <= internal_syndrome[elim_row_ptr+i] ^ tmp_s_coord;
                        end
                    end
                    elim_row_ptr <= elim_row_ptr + ELIMINATE_PER_CYCLE;
                    if (elim_row_ptr+ELIMINATE_PER_CYCLE-HEIGHT == 0) begin
                        elim_row_ptr <= '0;
                        col_search_ptr <= col_search_ptr + 1;
                        search_ptr <= '0;
                        state <= state - 1;
                        if (col_search_ptr == HEIGHT-1) begin
                            bitcount <= '0;
                            count_syndrome_ptr <= '0;
                            count_vect <= '0;
                            state <= state + 1;
                        end
                    end
                end
            popcount : begin
                    bitcount <= temp_bitcount + bitcount;
                    for (int i = 0; i < BITS_COUNTED_PER_CYCLE; i++) begin
                        count_vect[i] <= internal_syndrome[i+count_syndrome_ptr]; 
                    end
                    count_syndrome_ptr <= count_syndrome_ptr + BITS_COUNTED_PER_CYCLE;
                    if (count_syndrome_ptr == HEIGHT) begin
                        if (bitcount+temp_bitcount == TARGET_WEIGHT) begin
                            correct <= 1'b1;
                            state <= state + 1;
                            $write("%b\n", internal_syndrome);
                        end else begin
                            state <= '0;
                            done <= '1;
                        end
                    end 
                end
            stall : begin
                end
            default : begin
                state <= 0;
                done <= 1;
                correct <= 0;
            end
        endcase
    end
end

endmodule