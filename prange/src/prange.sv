`include "params.svh"

module prange (
    input CLOCK_125_p,
    input CLOCK_50_B5B,
    input CPU_RESET_n,
    
    output UART_TX,
    output [7:0] LEDG
);

`define CLK CLOCK_50_B5B // will change in future

reg mat_bit;
reg [GAUS_UNITS-1:0] gauss_ready;
reg [GAUS_UNITS-1:0] gauss_correct;
reg [$clog2(GAUS_UNITS)-1:0] broadcast_to;
reg broadcast_valid;

perm perm (.clk(`CLK), .reset(CPU_RESET_n), .seed_base(BASE_SEED),
    .ready(gauss_ready), .mat_bit(mat_bit), .broadcast_to(broadcast_to),
    .broadcast_valid_old(broadcast_valid));
/*
genvar i;
generate
    for (i = 0; i < GAUS_UNITS; i++) begin : gen_gauss
        gauss gauss (.clk(`CLK), .reset(CPU_RESET_n), .partial_mat(partial_mat),
            .broadcast_to(broadcast_to), .broadcast_target(($clog2(GAUS_UNITS))'(i)), .broadcast_valid(broadcast_valid),
            .done(gauss_ready[i]), .correct(gauss_correct[i]));
    end
endgenerate
*/
assign LEDG = |gauss_correct;

endmodule