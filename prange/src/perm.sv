`include "params.svh"

module perm (
    input [31:0] seed_base,
    input clk,
    input reset,

    output [(WIDTH/2)-1:0] [WIDTH_LOG2-1:0] perm_mat 
);

reg [WIDTH-1:0] [WIDTH_LOG2-1:0] internal_mat;
reg [31:0] new_seed;
reg [31:0] cur_seed;

always_comb begin
    new_seed = cur_seed;
    new_seed ^= new_seed << 13;
	new_seed ^= new_seed >> 17;
	new_seed ^= new_seed << 5;
end

always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        for (int i = 0; i < WIDTH; i++) begin
            internal_mat[i] <= i;
        end
        cur_seed <= 0;
    end else begin // the following can be repeated X times at the cost of timing and increase in randomness
        internal_mat[cur_seed[23:8]%WIDTH] <= internal_mat[new_seed[23:8]%WIDTH]; // constant modulos are not *great*, but it is a relatively minor cost
        internal_mat[new_seed[23:8]%WIDTH] <= internal_mat[cur_seed[23:8]%WIDTH];
        cur_seed <= (|cur_seed) ? new_seed : seed_base; // assign if the seed is zero, only true during initialization
    end
end

assign perm_mat[(WIDTH/2)-1:0] = internal_mat[(WIDTH/2)-1:0];

endmodule