`include "params.svh"

module prange (
    input CLOCK_125_p,
    input CLOCK_50_B5B,
    input CPU_RESET_n,
    
    output UART_TX
);

`define CLK CLOCK_50_B5B // will change in future

// unpacked array of 2d packed arrays
reg [(WIDTH/2)-1:0] [WIDTH_LOG2-1:0] perm_mat;
reg [GAUS_UNITS:0] gauss_ready;

perm perm (.clk(`CLK), .reset(CPU_RESET_n), .seed_base(BASE_SEED),
    .ready(gauss_ready), .perm_mat(perm_mat));

genvar i;
generate
    for (i = 0; i < GAUS_UNITS; i++) begin
        
    end
endgenerate



endmodule