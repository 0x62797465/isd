`include "../src/params.svh"

module prange_tb;
    localparam int iterations = 100000000;

    reg clk = 0;
    reg reset = 0;
    always #10 clk = ~clk;
    wire [7:0] LEDG;
    prange dut (.CLOCK_50_B5B(clk),
        .CPU_RESET_n(reset), .LEDG(LEDG), .LEDR(), .UART_TX());
    
    reg [GAUS_UNITS-1:0] ALREADY_VALID = 0;

    longint cycles = 0;
    longint eliminations = 0;
    longint perm_idle = 0;
    longint gauss_idle = 0;

    initial begin
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;
        for (int i = 0; i < iterations; i++) begin
            @(posedge clk);
            cycles = cycles + 1; 
            if (|LEDG) begin
                $fatal(2, "Found solution\n");
            end
            perm_idle = perm_idle + !dut.gen_unit[0].single_unit.broadcast_valid;
            if (cycles%1000000 == 0) begin
                $write("Total cycles: %d\nSuccessful total eliminations (estimate): %d\nPermutation idle (randomizing) for: %d\nGaussian idle for (estimate average): %d\nCurrent state: %d\n", 
                    cycles, eliminations*GAUS_UNITS*TOTAL_UNITS, perm_idle, gauss_idle, dut.gen_unit[0].single_unit.gen_gauss[0].gauss.state);
                $fflush();
            end
            eliminations = eliminations + (dut.gen_unit[0].single_unit.gen_gauss[0].gauss.state == dut.gen_unit[0].single_unit.gen_gauss[0].gauss.popcount_warmup);
            gauss_idle = gauss_idle + (dut.gen_unit[0].single_unit.gen_gauss[0].gauss.state == dut.gen_unit[0].single_unit.gen_gauss[0].gauss.uninitialized);
        end
        $write("Total cycles: %d\nSuccessful eliminations (estimate): %d\nPermutation idle (randomizing) for: %d\nGaussian idle for (estimate): %d\n", 
            cycles, eliminations*GAUS_UNITS*TOTAL_UNITS, perm_idle, gauss_idle);
        $finish();
    end
endmodule