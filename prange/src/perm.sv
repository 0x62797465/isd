`include "params.svh"

module perm (
    input [31:0] seed_base,
    input clk,
    input reset,
    input [GAUS_UNITS-1:0] ready,

    output reg mat_bit,
    output reg [$clog2(GAUS_UNITS)-1:0] broadcast_to,
    output reg broadcast_valid_old
);

localparam int words = (WIDTH-1)/32;
localparam logic [WIDTH*HEIGHT-1:0] tmp_matrix = `MATRIX;
(* ramstyle = "M10K" *) reg [31:0] original_matrix [(HEIGHT-1):0] [words:0]; // = `MATRIX; TODO: Fix matrix definition // more mem usage less circut complexity  
initial begin
    for (int a = 0; a < HEIGHT; a++) begin
        for (int b = 0; b < words+1; b++) begin
            for (int c = 0; c < 32; c++) begin
                original_matrix[a][b][c] = tmp_matrix[(a*WIDTH+b*32+c)%(WIDTH*HEIGHT-1)];
            end
        end
    end
end
reg [31:0] new_seed;
reg [31:0] cur_seed;

// xorshift32
always_comb begin
    new_seed = cur_seed;
    new_seed ^= new_seed << 13;
	new_seed ^= new_seed >> 17;
	new_seed ^= new_seed << 5;
end

// copying logic

reg [$clog2(WIDTH)-1:0] old_copy_ptr;
reg [$clog2(WIDTH)-1:0] copy_ptr; // technically can be unified, probably will be under synthesis, this is just for clarity
reg [$clog2(WIDTH/32):0] aligned_copy_ptr;
assign aligned_copy_ptr = copy_ptr/32; // word alignmnet

reg [$clog2(HEIGHT):0] col_ptr;

reg [$clog2(HEIGHT):0] row_ptr;
reg [$clog2(HEIGHT):0] old_row_ptr;
reg [$clog2(HEIGHT):0] older_row_ptr;



reg [31:0] read_buff;
always_ff @(posedge clk) begin
    read_buff <= original_matrix[row_ptr][aligned_copy_ptr];
end

 // this assumes that $clog2(HEIGHT) < 2^16; additionally it wastes memory to save compute
(* ramstyle = "M10K" *) reg [15:0] perm_snapshots [GAUS_UNITS:0] [WIDTH-1:0];
reg [15:0] perm_read_buff;
reg [15:0] perm_write_buff;
reg [15:0] perm_write_ptr;
reg [15:0] perm_read_ptr;
reg [$clog2(GAUS_UNITS):0] read_unit_ptr;
reg [$clog2(GAUS_UNITS):0] write_unit_ptr;
 
reg perm_we;
always_ff @(posedge clk) begin
    perm_read_buff <= perm_snapshots[read_unit_ptr][perm_read_ptr];
    if (perm_we)
        perm_snapshots[write_unit_ptr][perm_write_ptr] <= perm_write_buff;
end


// to sync up with BRAM access delay
reg broadcast_valid;
reg broadcast_valid_1;
reg broadcast_valid_2;
reg broadcast_valid_3;
always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        broadcast_valid_old <= '0;
        old_copy_ptr <= '0;
        broadcast_valid_1 <= '0;
        broadcast_valid_2 <= '0;
        broadcast_valid_3 <= '0;
    end else begin
        broadcast_valid_1 <= broadcast_valid;
        broadcast_valid_2 <= broadcast_valid_1;
        broadcast_valid_3 <= broadcast_valid_2;
        broadcast_valid_old <= broadcast_valid_3;
        old_copy_ptr <= copy_ptr;
    end
end

reg [GAUS_UNITS-1:0] [$clog2(GAUS_UNITS):0] rename_table;
reg [$clog2(GAUS_UNITS):0] free_ptr;

reg [2:0] randomizer_state;
reg initialized; 
always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        initialized <= '0;
        broadcast_to <= 0;
        for (int i = 0; i < GAUS_UNITS; i++) begin
            rename_table[i] <= i;
        end
        free_ptr <= GAUS_UNITS;
        cur_seed <= seed_base;
        copy_ptr <= 0;
        broadcast_valid <= 0;
        perm_we <= 1; // for initialization
        write_unit_ptr <= '0;
        perm_write_ptr <= '0;
        perm_write_buff <= '0;
        randomizer_state <= '0;
        perm_read_ptr <= '0;
    end else begin
        if (!initialized) begin
            perm_write_ptr <= perm_write_ptr + 1;
            perm_write_buff <= perm_write_ptr + 1;
            if (perm_write_ptr == WIDTH-1) begin
                if (write_unit_ptr == GAUS_UNITS+1) begin
                    initialized <= '1;
                    perm_we <= '0;
                end
                perm_write_ptr <= '0;
                free_ptr <= GAUS_UNITS;
                perm_write_buff <= '0;
                write_unit_ptr <= write_unit_ptr + 1;
            end
        end else begin
            if (broadcast_valid || broadcast_valid_old) begin
                old_row_ptr <= older_row_ptr;
                row_ptr <= old_row_ptr;
                // this echos bit by bit of the row 
                mat_bit <= read_buff[old_copy_ptr%32];
                perm_read_ptr <= col_ptr;
                col_ptr <= col_ptr + 1; 
                copy_ptr <= perm_read_buff;
            
                if (col_ptr == HEIGHT) begin
                    if (row_ptr+1 == HEIGHT) begin
                        broadcast_valid <= '0;
                    end
                    older_row_ptr <= older_row_ptr + 1;
                    perm_read_ptr <= 0;
                    col_ptr <= 1;
                end
            end else if (|ready && randomizer_state==0) begin 
                perm_we <= '0;
                for (int i = 0; i < GAUS_UNITS; i++) begin
                    if (ready[i]) begin // the amount of units should be small enough for a priority encoder to not break timing
                        // set to target permutation
                        read_unit_ptr <= free_ptr;
                        write_unit_ptr <= free_ptr;

                        // swap auxilarly and just-used matrix
                        rename_table[i] <= free_ptr;
                        free_ptr <= rename_table[i];

                        // initialize pointers
                        perm_read_ptr <= '0;
                        row_ptr <= '0;
                        older_row_ptr <= '0;
                        old_row_ptr <= '0;
                        col_ptr <= 1;
                        
                        // set output signal
                        broadcast_to <= i;
                        broadcast_valid <= '1;
                        break;
                    end
                end
            end else begin // The state machine is needed because a single swap requires many memory operations
                case (randomizer_state) 
                    3'd0 : begin
                        perm_we <= '0;
                        randomizer_state <= randomizer_state + 1;
                        write_unit_ptr <= free_ptr;
                        read_unit_ptr <= free_ptr;
                        perm_read_ptr <= (new_seed[23:8]%(WIDTH/2))+(WIDTH/2);
                    end
                    3'd1 : begin // technically can be shortened by a cycle via a specific BRAM config (need to define if RAW or WAR occurs when set same cycle)
                        perm_we <= '0;
                        randomizer_state <= randomizer_state + 1;
                        perm_read_ptr <= (cur_seed[23:8]%(WIDTH/2));
                    end
                    3'd2 : begin
                        perm_we <= 1;
                        randomizer_state <= randomizer_state + 1;
                        perm_write_ptr <= (cur_seed[23:8]%(WIDTH/2));
                        perm_write_buff <= perm_read_buff;
                    end
                    3'd3 : begin
                        perm_we <= 1;
                        randomizer_state <= 0;
                        perm_write_ptr <= (new_seed[23:8]%(WIDTH/2))+(WIDTH/2);
                        perm_write_buff <= perm_read_buff;
                        cur_seed <= (|cur_seed) ? new_seed : seed_base; 
                    end
                endcase
            end
        end
    end
end

endmodule