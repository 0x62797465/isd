`include "params.svh"

module gauss (
    input clk,
    input reset,
    input [OUTPUT_WIDTH-1:0] partial_mat,
    input [$clog2(GAUS_UNITS)-1:0] broadcast_to,
    input [$clog2(GAUS_UNITS)-1:0] broadcast_target,
    input broadcast_valid,

    output reg done,
    output reg correct
);

localparam int receive = 0;
localparam int select = 1;
localparam int eliminate = 2;
localparam int popcount = 3;
localparam int stall = 4;


reg [$clog2(HEIGHT)-1:0] col_ptr;
reg [$clog2(HEIGHT)-1:0] copy_ptr;
reg [HEIGHT-1:0] [HEIGHT-1:0] internal_mat;
reg [HEIGHT-1:0] internal_syndrome;
reg [2:0] state; // receive, select, eliminate, popcount 

reg [$clog2(HEIGHT)-1:0] search_ptr;
reg [$clog2(HEIGHT)-1:0] col_search_ptr;
reg tmp_s_coord;
reg [HEIGHT-1:0] tmp_vect;

reg [$clog2(HEIGHT)-1:0] elim_row_ptr;

reg [$clog2(HEIGHT)-1:0] count_syndrome_ptr;
reg [$clog2(HEIGHT)-1:0] bitcount;
reg [$clog2(BITS_COUNTED_PER_CYCLE)-1:0] temp_bitcount;
reg [BITS_COUNTED_PER_CYCLE-1:0] count_vect;

always_comb begin
    for (int i = 0; i < BITS_COUNTED_PER_CYCLE; i++) begin
        
    end
end

always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        copy_ptr <= 0;
        col_ptr <= 0;
        correct <= 0;
        state <= 0;
        done <= 1;
    end else begin
        case (state)
            receive : begin
                    internal_syndrome <= `SYNDROME;
                    col_search_ptr <= '0;
                    if (broadcast_valid && broadcast_to == broadcast_target) begin
                        for (int i = 0; i < OUTPUT_WIDTH; i++) begin
                            internal_mat[copy_ptr+i][col_ptr] <= partial_mat[i];
                        end
                        if (copy_ptr+OUTPUT_WIDTH-HEIGHT-1) begin
                            copy_ptr <= copy_ptr + OUTPUT_WIDTH;
                            if (col_ptr == (HEIGHT-1)) begin // note, can be incorrect, check during tb
                                state <= state + 1;
                                done <= '0;
                            end
                        end else begin
                            copy_ptr <= '0;
                            col_ptr <= col_ptr + 1;
                        end
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
                    if (SEARCH_PER_CYCLE+search_ptr >= HEIGHT-1) begin
                        state <= '0;
                        done <= '1;
                    end
                    for (int i = 0; i < SEARCH_PER_CYCLE && i+search_ptr <= HEIGHT-1; i++) begin
                        if (internal_mat[i+search_ptr][col_search_ptr]) begin 
                            // originally was going to be a rename structure, but would require a tree-based approach and increase 
                            // logic usage too much
                            internal_mat[col_search_ptr] <= internal_mat[i+search_ptr];
                            internal_mat[i+search_ptr] <= internal_mat[col_search_ptr];
                            // improve naming convention!!!!
                            internal_syndrome[col_search_ptr] <= internal_syndrome[i+search_ptr];
                            internal_syndrome[i+search_ptr] <= internal_syndrome[col_search_ptr];
                            state <= state + 1;
                            elim_row_ptr <= '0;
                            tmp_s_coord <= internal_syndrome[i+search_ptr];
                            tmp_vect <= internal_mat[i+search_ptr];
                            break;
                        end
                    end
                end
            eliminate : begin // ~~note to self: see if REF is faster/better circut complexity (answer is likely yes)~~ do NOT do this
                    for (int i = 0; i < ELIMINATE_PER_CYCLE; i++) begin
                        if (internal_mat[elim_row_ptr+i][col_search_ptr] && // if the bit needs to be flipped
                            (col_search_ptr != elim_row_ptr+i)) begin // and it's not the row we're using for elimination
                                internal_mat[elim_row_ptr+i] <= internal_mat[elim_row_ptr+i] ^ tmp_vect;
                                internal_syndrome[elim_row_ptr+i] <= internal_syndrome[elim_row_ptr+i] ^ tmp_s_coord;
                        end
                    end
                    elim_row_ptr <= elim_row_ptr + ELIMINATE_PER_CYCLE;
                    if (elim_row_ptr+ELIMINATE_PER_CYCLE-HEIGHT == 0) begin
                        elim_row_ptr <= '0;
                        col_search_ptr <= col_search_ptr + 1;
                        search_ptr <= col_search_ptr + 1;
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
                    if (count_syndrome_ptr+BITS_COUNTED_PER_CYCLE == HEIGHT) begin
                        if (bitcount == TARGET_WEIGHT) begin
                            correct <= 1'b1;
                            state <= state + 1;
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