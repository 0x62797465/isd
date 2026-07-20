`include "../src/params.svh"

module prange_tb;
    reg clk = 0;
    reg reset = 0;
    always #10 clk = ~clk;
    wire [7:0] LEDG;
    prange dut (.CLOCK_125_p(clk), .CLOCK_50_B5B(clk),
        .CPU_RESET_n(reset), .LEDG(LEDG));
    
    reg [GAUS_UNITS-1:0] ALREADY_VALID = 0;
    initial begin
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;
        for (int i = 0; i < 1000100000; i++) begin
            @(posedge clk);
            if (LEDG) begin
                for (int i = 0; i < GAUS_UNITS; i++) begin
                    if (dut.gauss_correct[i] && !ALREADY_VALID[i]) begin
                        ALREADY_VALID[i] = 1'b1;
                        for (int a = 0; a < HEIGHT; a++) begin
                            $write("%h ", dut.perm.perm_snapshots[i][a]);
                        end
                        $write("\n");
                    end
                end
            end
        end
        $finish();
    end
endmodule