`include "params.svh"

module prange (
    input CLOCK_125_p,
    input CLOCK_50_B5B,
    input CPU_RESET_n,
    
    output UART_TX
);

`define CLK CLOCK_50_B5B // will change in future

// unpacked array of 2d packed arrays
reg [(WIDTH/2)-1:0] [WIDTH_LOG2-1:0] perm_mat [0:PERMUTATE_AMOUNT-1];

genvar i;
generate
    for (i = 0; i < PERMUTATE_AMOUNT; i++) begin
        perm perm (.clk(`CLK), .reset(CPU_RESET_n), .seed_base(BASE_SEED+i),
            .perm_mat(perm_mat[i]));
    end
endgenerate


endmodule