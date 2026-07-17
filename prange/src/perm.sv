`include "params.svh"

module perm (
    input [31:0] seed_base,
    input clk,
    input reset,
    input [GAUS_UNITS:0] ready,

    output reg [OUTPUT_WIDTH-1:0] partial_mat,
    output reg [$clog2(GAUS_UNITS)-1:0] broadcast_to,
    output reg broadcast_valid
);

reg [WIDTH-1:0][HEIGHT-1:0] original_matrix = `MATRIX;
reg [(WIDTH/2)-1:0] [WIDTH_LOG2-1:0] perm_snapshots [GAUS_UNITS-1:0];
reg [WIDTH-1:0] [WIDTH_LOG2-1:0] internal_mat;
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
reg [$clog2(HEIGHT)-1:0] copy_ptr;
reg [$clog2(WIDTH/2)-1:0] col_ptr;
reg [$clog2(WIDTH)-1:0] per_col_ptr;

always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        broadcast_to <= 0;
        for (int i = 0; i < WIDTH; i++) begin
            internal_mat[i] <= i;
        end
        cur_seed <= seed_base;
        copy_ptr <= 0;
        broadcast_valid <= 0;
    end else begin 
        if (broadcast_valid) begin
            // this echos column by column because of permutation lookups
            // however it may be better for the gauss units if we wrote row by row
            // a compromise would be to have a middle layer that transposes while writing
            // which avoids the lookup cost, but I am unsure. For now it will stay as is 
            for (int i = 0; i < OUTPUT_WIDTH; i++) begin
                partial_mat[i] <= original_matrix[per_col_ptr][copy_ptr+i];
            end
            if (!(copy_ptr+OUTPUT_WIDTH-HEIGHT)) begin
                copy_ptr <= 0;
                col_ptr <= col_ptr + 1;
                per_col_ptr <= perm_snapshots[broadcast_to][col_ptr + 1];
            end else
                copy_ptr <= copy_ptr+OUTPUT_WIDTH;
            if (col_ptr == HEIGHT)
                broadcast_valid = 1'b0;
        end else if (|ready) begin 
            for (int i = 0; i < GAUS_UNITS; i++) begin
                if (ready[i]) begin // the amount of units should be small enough for a priority encoder to not break timing
                    broadcast_to <= i;
                    perm_snapshots[i] <= internal_mat; // might have to make partial copy later
                    broadcast_valid <= 1'b1;
                    copy_ptr <= 0;
                    per_col_ptr <= internal_mat[0];
                    col_ptr <= 0;
                    break;
                end
            end
        end 
        // the following can be repeated X times at the cost of timing and increase in randomness and checks of confliction
        internal_mat[cur_seed[23:8]%(WIDTH/2)] <= internal_mat[(new_seed[23:8]%(WIDTH/2))+(WIDTH/2)]; // constant modulos are not *great*, but it is a relatively minor cost
        internal_mat[(new_seed[23:8]%(WIDTH/2))+(WIDTH/2)] <= internal_mat[cur_seed[23:8]%(WIDTH/2)];
        cur_seed <= (|cur_seed) ? new_seed : seed_base; // assign if the seed is zero, only true during initialization
    end
end

endmodule