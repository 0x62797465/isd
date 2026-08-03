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

reg [63:0] new_seed;
reg [63:0] cur_seed;

// xorshift64
always_comb begin
    new_seed = cur_seed;
    new_seed ^= new_seed << 13;
	new_seed ^= new_seed >> 7;
	new_seed ^= new_seed << 17;
end

// matrix logic & definition
localparam int WIDTH_MAT = WIDTH+1;
localparam int WORDS = WIDTH_MAT/32+1;
localparam reg [WIDTH*HEIGHT-1:0] tmp_matrix = `MATRIX;
localparam reg [HEIGHT-1:0] tmp_syndrome = `SYNDROME;
(* ramstyle = "M10K" *) reg [31:0] original_matrix [HEIGHT*WORDS-1:0]; // flattened to prevent synthesis from needing to infer intent
// this is synthesized as ROM (no LUT usage; setup is purely a synthesis time operation)
initial begin 
    for (int a = 0; a < HEIGHT; a++) begin
        for (int b = 0; b < WIDTH; b++) begin
            original_matrix[a*WORDS+b/32][b%32] = tmp_matrix[(a*WIDTH+b)];
        end
        original_matrix[a*WORDS+WIDTH/32][(WIDTH)%32] = tmp_syndrome[a];
    end
end

struct {
    reg [$clog2(WIDTH_MAT)-1:0] col_ptr;
    reg [$clog2(WIDTH_MAT)-1:0] col_old;
    reg [$clog2(WIDTH_MAT/32):0] col_aligned; // extra bit since int div rounds down

    reg [$clog2(HEIGHT):0] row_ptr; // extra bits to account for logic behavior
    reg [$clog2(HEIGHT):0] row_old;
    reg [$clog2(HEIGHT):0] row_older;

    reg [$clog2(HEIGHT*WORDS-1)-1:0] read_addr; 

    reg [31:0] read_buff;
} mat;
assign mat.col_aligned = mat.col_ptr/32; // word alignment

// (* multstyle = "dsp" *) // optional hint; may not be optimal to make DSPs since the multiplier is fixed
always_comb
    mat.read_addr = mat.row_ptr[$clog2(HEIGHT)-1:0]*WORDS+mat.col_aligned;

always_ff @(posedge clk) begin
    mat.read_buff <= original_matrix[mat.read_addr];
end

// permutation r/w logic & registers
localparam SNAPSHOTS_AMOUNT = GAUS_UNITS+1;
(* ramstyle = "M10K" *) reg [15:0] perm_snapshots [SNAPSHOTS_AMOUNT*WIDTH_MAT-1:0];
struct {
    reg we;

    reg [15:0] read_buff;
    reg [15:0] write_buff;
    
    reg [$clog2(WIDTH_MAT):0] write_ptr;
    reg [$clog2(SNAPSHOTS_AMOUNT)-1:0] write_unit;
    reg [SNAPSHOTS_AMOUNT*WIDTH_MAT-1:0] p_write_addr;

    reg [$clog2(WIDTH_MAT):0] read_ptr;
    reg [$clog2(SNAPSHOTS_AMOUNT)-1:0] read_unit;
    reg [$clog2(WIDTH_MAT*16):0] read_unaligned;
    reg [SNAPSHOTS_AMOUNT*WIDTH_MAT-1:0] p_read_addr;
    
    reg [GAUS_UNITS-1:0] [$clog2(SNAPSHOTS_AMOUNT)-1:0] rename_table;
    reg [$clog2(SNAPSHOTS_AMOUNT)-1:0] free_ptr;
} perm;

always_comb
    perm.p_read_addr = perm.read_unit*WIDTH_MAT+perm.read_ptr;

always_comb
    perm.p_write_addr = perm.write_unit*WIDTH_MAT+perm.write_ptr;

always_ff @(posedge clk) begin
    perm.read_buff <= perm_snapshots[perm.p_read_addr];
    if (perm.we)
        perm_snapshots[perm.p_write_addr] <= perm.write_buff;
end


// to sync up with BRAM access delay and communication delay
reg broadcast_valid;
reg broadcast_valid_1;
reg broadcast_valid_2;
reg broadcast_valid_3;
always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        broadcast_valid_old <= '0;
        broadcast_valid_1 <= '0;
        broadcast_valid_2 <= '0;
        broadcast_valid_3 <= '0;
        
        mat.col_old <= '0;
    end else begin
        broadcast_valid_1 <= broadcast_valid;
        broadcast_valid_2 <= broadcast_valid_1;
        broadcast_valid_3 <= broadcast_valid_2;
        broadcast_valid_old <= broadcast_valid_3;

        mat.col_old <= mat.col_ptr;
    end
end

// transmission regs
reg tm_initialized;
reg freeze;

// state regs
reg [2:0] randomizer_state;
reg initialized; 
reg [$clog2(NEEDED_CYCLES_IDLE):0] cycles_idle;

// core logic
always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        for (int i = 0; i < GAUS_UNITS; i++) begin
            perm.rename_table[i] <= i; // too small to need to be put in the initialization stage
        end
        perm.we <= 1; // for initialization state
        perm.write_unit <= '0;
        perm.write_ptr <= '0;
        perm.write_buff <= '0;
        perm.read_ptr <= '0;
        perm.free_ptr <= SNAPSHOTS_AMOUNT-1;
        
        randomizer_state <= '0;
        initialized <= '0;

        freeze <= 0;
        tm_initialized <= 0;
        
        broadcast_to <= 0;
        broadcast_valid <= 0;

        cur_seed <= '0;
        
        mat.col_ptr <= 0;
    end else begin
        if (!initialized) begin
            cycles_idle <= '0;
            // sets all permutation snapshots (and the free one) to 1...N pointers
            perm.write_ptr <= perm.write_ptr + 1;
            perm.write_buff <= perm.write_ptr + 1;
            if (perm.write_ptr == WIDTH) begin
                if (perm.write_unit == SNAPSHOTS_AMOUNT-1) begin
                    initialized <= '1;
                    perm.we <= '0;
                    cur_seed <= seed_base; 
                end
                perm.write_ptr <= '0;
                perm.free_ptr <= SNAPSHOTS_AMOUNT-1;
                perm.write_buff <= '0;
                perm.write_unit <= perm.write_unit + 1;
            end
        end else if (recv_ready) begin 
            freeze <= 1;
            if (!tm_initialized) begin
                tm_initialized <= 1;
                for (int i = 0; i < GAUS_UNITS; i++) begin
                    if (correct[i]) begin
                        perm.read_unit <= perm.rename_table[i];
                        perm.read_ptr <= HEIGHT;
                        perm.read_unaligned <= HEIGHT*16;
                    end
                end
            end else begin
                if (recv_next) begin
                    perm.read_unaligned <= perm.read_unaligned + 1;
                    perm.read_ptr <= (perm.read_unaligned + 1)/16;
                end
                transmit_bit <= perm.read_buff[(perm.read_unaligned)%16];
            end
        end else if (freeze) begin
            tm_initialized <= 0;
        end else begin
            if (broadcast_valid || broadcast_valid_old) begin
                // cycle delayed row pointer
                mat.row_old <= mat.row_older;
                mat.row_ptr <= mat.row_old;
                
                // this echoes bit by bit of the row 
                mat_bit <= mat.read_buff[mat.col_old%32];

                // set permutation reading
                perm.read_ptr <= perm.read_ptr + 1;
                
                // set column pointer based off previous read permutation pointer
                mat.col_ptr <= perm.read_buff;
            
                if (perm.read_ptr == HEIGHT*2) begin
                    if (mat.row_ptr+1 == HEIGHT) begin
                        broadcast_valid <= '0;
                        cycles_idle <= '0;
                    end
                    mat.row_older <= mat.row_older + 1;
                    perm.read_ptr <= HEIGHT;
                end
            end else if (|ready && randomizer_state==0 && cycles_idle > NEEDED_CYCLES_IDLE) begin // depends on state to prevent partial swaps 
                perm.we <= '0;
                for (int i = 0; i < GAUS_UNITS; i++) begin
                    if (ready[i]) begin // the amount of units should be small enough for a priority encoder to not break timing
                        // set to target permutation
                        perm.read_unit <= perm.free_ptr;
                        perm.write_unit <= perm.free_ptr;

                        // swap auxiliary and just-used matrix
                        perm.rename_table[i] <= perm.free_ptr;
                        perm.free_ptr <= perm.rename_table[i];

                        // initialize pointers
                        perm.read_ptr <= HEIGHT;
                        mat.row_ptr <= '0;
                        mat.row_older <= '0;
                        mat.row_old <= '0;
                        
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
                        perm.we <= '0;
                        randomizer_state <= randomizer_state + 1;
                        perm.write_unit <= perm.free_ptr;
                        perm.read_unit <= perm.free_ptr;
                        // prevents division in hardware by failing if any of the randomly generated numbers 
                        // are above a readable index in the free permutation snapshot
                        if (WIDTH/2-1 < new_seed[$clog2(WIDTH/2)+8-1:8] || WIDTH/2-1 < cur_seed[$clog2(WIDTH/2)+8-1:8]) begin
                            cur_seed <= new_seed; 
                            randomizer_state <= '0;
                        end else 
                            perm.read_ptr <= (new_seed[$clog2(WIDTH/2)+8-1:8])+(WIDTH/2);
                    end
                    3'd1 : begin
                        perm.we <= '0;
                        randomizer_state <= randomizer_state + 1;
                        perm.read_ptr <= (cur_seed[$clog2(WIDTH/2)+8-1:8]);
                    end
                    3'd2 : begin
                        perm.we <= 1;
                        randomizer_state <= randomizer_state + 1;
                        perm.write_ptr <= (cur_seed[$clog2(WIDTH/2)+8-1:8]);
                        perm.write_buff <= perm.read_buff;
                    end
                    3'd3 : begin
                        perm.we <= 1;
                        randomizer_state <= 0;
                        perm.write_ptr <= (new_seed[$clog2(WIDTH/2)+8-1:8])+(WIDTH/2);
                        perm.write_buff <= perm.read_buff;
                        cur_seed <= new_seed; 
                    end
                endcase
            end
        end
    end
end

endmodule
