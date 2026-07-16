`include "../src/params.svh"

module perm_tb;
    reg clk = 0;
    reg reset = 0;
    reg [31:0] seed_base = '1;
    reg [(WIDTH/2)-1:0] [WIDTH_LOG2-1:0] perm_mat = '0;
    always #10 clk = ~clk;

    perm dut (.clk(clk), .reset(reset), .seed_base(seed_base), 
        .perm_mat(perm_mat));

    // basic randomness assertions
    assert property (@(posedge clk)
        disable iff (!reset || dut.cur_seed == seed_base)
        dut.new_seed != dut.cur_seed
    )
    else begin
        $fatal(2, "Random seed same as previous, new: %d, prev: %d\n", 
            dut.new_seed, dut.cur_seed);
    end

    assert property (@(posedge clk)
        disable iff (!reset || dut.cur_seed == seed_base)
        dut.new_seed != '0
    )
    else begin
        $fatal(2, "Random seed is zero, prev: %d\n", 
            $past(dut.new_seed));
    end

    // drive for a fixed amount of cycles; make sure permutation state is sane
    reg perm_invalid = 0;
    initial begin
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;
        for (int i = 0; i < 10000; i++) begin
            @(posedge clk);
            for (int a = 0; a < ((WIDTH/2)); a++) begin
                for (int b = 0; b < ((WIDTH/2)); b++) begin
                    if (a != b)
                        perm_invalid |= perm_mat[a] == perm_mat[b];
                end
            end
            if (perm_invalid) begin
                $fatal(2, "Impossible permutation state reached\n");
            end
        end
        $finish();
    end
endmodule
