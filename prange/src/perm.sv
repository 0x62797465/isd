`include "params.svh"

module perm (
    input [31:0] seed_base,
    input clk,
    input reset,
    input [GAUS_UNITS-1:0] ready,
    input [GAUS_UNITS-1:0] correct,
    input recv_ready,
    input recv_next,

    output reg mat_bit,
    output reg transmit_bit,
    output reg [$clog2(GAUS_UNITS)-1:0] broadcast_to,
    output reg broadcast_valid_old
);

localparam int WORDS = (WIDTH+1)/32;
localparam logic [WIDTH*HEIGHT-1:0] tmp_matrix = `MATRIX;
localparam logic [HEIGHT-1:0] tmp_syndrome = `SYNDROME;
(* ramstyle = "M10K" *) reg [31:0] original_matrix [(HEIGHT*(WORDS+1)-1):0]; // = `MATRIX; TODO: Fix matrix definition // more mem usage less circut complexity  
initial begin
    for (int a = 0; a < HEIGHT; a++) begin
        for (int b = 0; b < WIDTH; b++) begin
            original_matrix[a*(WORDS+1)+b/32][b%32] = tmp_matrix[(a*WIDTH+b)];
        end
        original_matrix[a*(WORDS+1)+WIDTH/32][(WIDTH)%32] = tmp_syndrome[a];
    end
end
reg [63:0] new_seed;
reg [63:0] cur_seed;

// xorshift64
always_comb begin
    new_seed = cur_seed;
    new_seed ^= new_seed << 13;
	new_seed ^= new_seed >> 7;
	new_seed ^= new_seed << 17;
end

// copying logic

reg [$clog2(WIDTH+1)-1:0] old_copy_ptr;
reg [$clog2(WIDTH+1)-1:0] copy_ptr; // technically can be unified, probably will be under synthesis, this is just for clarity
reg [$clog2((WIDTH+1)/32):0] aligned_copy_ptr;
assign aligned_copy_ptr = copy_ptr/32; // word alignmnet

reg [$clog2(HEIGHT):0] row_ptr;
reg [$clog2(HEIGHT):0] old_row_ptr;
reg [$clog2(HEIGHT):0] older_row_ptr;

reg [$clog2((HEIGHT*(WORDS+1)-1))-1:0] read_addr; 

(* multstyle = "dsp" *)
always_comb
    read_addr = row_ptr[$clog2(HEIGHT)-1:0]*(WORDS+1)+aligned_copy_ptr;

reg [31:0] read_buff;
always_ff @(posedge clk) begin
    read_buff <= original_matrix[read_addr];
end

 // this assumes that $clog2(HEIGHT) < 2^16; additionally it wastes memory to save compute
(* ramstyle = "M10K" *) reg [15:0] perm_snapshots [(GAUS_UNITS+1)*(WIDTH+1)-1:0];
reg [15:0] perm_read_buff;
reg [15:0] perm_write_buff;
reg [$clog2(WIDTH+1):0] perm_write_ptr;
reg [$clog2(WIDTH+1):0] perm_read_ptr;
reg [$clog2((WIDTH+1)*16):0] unaligned_perm_read_ptr;
reg [$clog2(GAUS_UNITS):0] read_unit_ptr;
reg [$clog2(GAUS_UNITS):0] write_unit_ptr;
 
reg [(GAUS_UNITS+1)*(WIDTH+1)-1:0] p_read_addr;
reg [(GAUS_UNITS+1)*(WIDTH+1)-1:0] p_write_addr;

always_comb
    p_read_addr = read_unit_ptr*(WIDTH+1)+perm_read_ptr;

always_comb
    p_write_addr = write_unit_ptr*(WIDTH+1)+perm_write_ptr;

reg perm_we;
always_ff @(posedge clk) begin
    perm_read_buff <= perm_snapshots[p_read_addr];
    if (perm_we)
        perm_snapshots[p_write_addr] <= perm_write_buff;
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

// transmittion logic
reg tm_initialized;

reg [GAUS_UNITS-1:0] [$clog2(GAUS_UNITS):0] rename_table;
reg [$clog2(GAUS_UNITS):0] free_ptr;

reg [$clog2(NEEDED_CYCLES_IDLE):0] cycles_idle;

reg [2:0] randomizer_state;
reg initialized; 
always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        initialized <= '0;
        broadcast_to <= 0;
        for (int i = 0; i < GAUS_UNITS; i++) begin
            rename_table[i] <= i; // likely too small to need to be initialized
        end
        free_ptr <= GAUS_UNITS;
        cur_seed <= '0;
        copy_ptr <= 0;
        broadcast_valid <= 0;
        perm_we <= 1; // for initialization
        write_unit_ptr <= '0;
        perm_write_ptr <= '0;
        perm_write_buff <= '0;
        randomizer_state <= '0;
        perm_read_ptr <= '0;
        tm_initialized <= 0;
    end else begin
        if (!initialized) begin
            cycles_idle <= '0;
            // sets all permutation snapshots (and the free one) to 1...N pointers
            perm_write_ptr <= perm_write_ptr + 1;
            perm_write_buff <= perm_write_ptr + 1;
            if (perm_write_ptr == WIDTH) begin
                if (write_unit_ptr == GAUS_UNITS) begin
                    initialized <= '1;
                    perm_we <= '0;
                end
                perm_write_ptr <= '0;
                free_ptr <= GAUS_UNITS;
                perm_write_buff <= '0;
                write_unit_ptr <= write_unit_ptr + 1;
            end
        end else if (recv_ready) begin 
            if (!tm_initialized) begin
                tm_initialized <= '1;
                for (int i = 0; i < GAUS_UNITS; i++) begin
                    if (correct[i]) begin
                        read_unit_ptr <= rename_table[i];
                        perm_read_ptr <= HEIGHT;
                        unaligned_perm_read_ptr <= HEIGHT*16;
                    end
                end
            end else begin
                if (recv_next) begin
                    unaligned_perm_read_ptr <= unaligned_perm_read_ptr + 1;
                    perm_read_ptr <= (unaligned_perm_read_ptr + 1)/16;
                end
                transmit_bit <= perm_read_buff[(unaligned_perm_read_ptr)%16];
            end
        end else begin
            if (broadcast_valid || broadcast_valid_old) begin
                // cycle delayed row pointer
                old_row_ptr <= older_row_ptr;
                row_ptr <= old_row_ptr;
                
                // this echos bit by bit of the row 
                mat_bit <= read_buff[old_copy_ptr%32];

                // set permutation reading
                perm_read_ptr <= perm_read_ptr + 1;
                
                // set column pointer based off previous read permutation pointer
                copy_ptr <= perm_read_buff;
            
                if (perm_read_ptr == HEIGHT*2) begin
                    if (row_ptr+1 == HEIGHT) begin
                        broadcast_valid <= '0;
                        cycles_idle <= '0;
                    end
                    older_row_ptr <= older_row_ptr + 1;
                    perm_read_ptr <= HEIGHT;
                end
            end else if (|ready && randomizer_state==0 && cycles_idle > NEEDED_CYCLES_IDLE) begin // depends on state to prevent partial swaps 
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
                        perm_read_ptr <= HEIGHT;
                        row_ptr <= '0;
                        older_row_ptr <= '0;
                        old_row_ptr <= '0;
                        
                        // set output signal
                        broadcast_to <= i;
                        broadcast_valid <= '1;
                        break;
                    end
                end
            end else begin // The state machine is needed because a single swap requires many memory operations
                cycles_idle <= cycles_idle + 1;
                case (randomizer_state) 
                    3'd0 : begin
                        perm_we <= '0;
                        randomizer_state <= randomizer_state + 1;
                        write_unit_ptr <= free_ptr;
                        read_unit_ptr <= free_ptr;
                        // prevents division in hardware
                        if (WIDTH/2-1 < new_seed[$clog2(WIDTH/2)+8-1:8] || WIDTH/2-1 < cur_seed[$clog2(WIDTH/2)+8-1:8]) begin
                            cur_seed <= (|cur_seed) ? new_seed : seed_base; 
                            randomizer_state <= '0;
                        end else 
                            perm_read_ptr <= (new_seed[$clog2(WIDTH/2)+8-1:8])+(WIDTH/2);
                    end
                    3'd1 : begin // technically can be shortened by a cycle via a specific BRAM config (need to define if RAW or WAR occurs when set same cycle)
                        perm_we <= '0;
                        randomizer_state <= randomizer_state + 1;
                        perm_read_ptr <= (cur_seed[$clog2(WIDTH/2)+8-1:8]);
                    end
                    3'd2 : begin
                        perm_we <= 1;
                        randomizer_state <= randomizer_state + 1;
                        perm_write_ptr <= (cur_seed[$clog2(WIDTH/2)+8-1:8]);
                        perm_write_buff <= perm_read_buff;
                    end
                    3'd3 : begin
                        perm_we <= 1;
                        randomizer_state <= 0;
                        perm_write_ptr <= (new_seed[$clog2(WIDTH/2)+8-1:8])+(WIDTH/2);
                        perm_write_buff <= perm_read_buff;
                        cur_seed <= (|cur_seed) ? new_seed : seed_base; 
                    end
                endcase
            end
        end
    end
end

endmodule
