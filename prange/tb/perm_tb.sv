`include "../src/params.svh"

module perm_tb;
    reg clk = 0;
    reg reset = 0;
    reg [31:0] seed_base = '1;
    reg [GAUS_UNITS:0] ready = '0;
    reg [OUTPUT_WIDTH-1:0] partial_mat = '0;
    reg [$clog2(GAUS_UNITS)-1:0] broadcast_to = '0;
    reg broadcast_valid = '0;
    always #10 clk = ~clk;

    perm dut (.clk(clk), .reset(reset), .seed_base(seed_base),
        .ready(ready), .partial_mat(partial_mat), .broadcast_to(broadcast_to),
        .broadcast_valid(broadcast_valid));

    // basic randomness assertions
    assert property (
        @(posedge clk)
        disable iff (!reset)
        (dut.cur_seed != seed_base) |-> (dut.new_seed != dut.cur_seed)
    )
    else begin
        $fatal(2, "Random seed same as previous, new: %d, prev: %d\n", 
            dut.new_seed, dut.cur_seed);
    end

    assert property (
        @(posedge clk)
        disable iff (!reset)
        (dut.cur_seed == seed_base) || (dut.new_seed != '0)
    )
    else begin
        $fatal(2, "Random seed incorrectly zero, new: %d, prev: %d\n", 
            dut.new_seed, dut.cur_seed);
    end

    assert property (
        @(posedge clk)
        disable iff (!reset)
        $past(|ready) |=> broadcast_valid // if the past was ready, then the current is valid
    )
    else begin
        $fatal(2, "Broadcast is incorrectly low: %d\n", 
            $past(dut.new_seed));
    end

    reg [HEIGHT*HEIGHT-1:0] permutated_matrix = '0;
    reg [$clog2(HEIGHT*HEIGHT):0] acum = '0;
    reg perm_invalid = 0;
    reg [(WIDTH/2)-1:0] [WIDTH_LOG2-1:0] guessed_permutation = '0;
    reg [WIDTH*HEIGHT-1:0] original_matrix_clone = `MATRIX;
    reg guess_val;
    initial begin
        // drive for a fixed amount of cycles; make sure permutation state is sane
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;
        for (int i = 0; i < 10000; i++) begin
            @(posedge clk);
            for (int a = 0; a < ((WIDTH/2)); a++) begin
                for (int b = 0; b < ((WIDTH/2)); b++) begin
                    if (a != b)
                        perm_invalid |= dut.internal_mat[a] == dut.internal_mat[b];
                end
            end
            if (perm_invalid) begin
                $fatal(2, "Impossible permutation state reached\n");
            end
        end
        // test transfer protocal 
        ready[1] = 1'b1;
        @(posedge clk); // recieved
        @(posedge clk); // broadcast logic initial
        @(posedge clk); // should have valid broadcast out
        ready[1] = 1'b0;
        assert(broadcast_to == 1)
            else $fatal(2, "Broadcast is to the wrong unit\n");
        acum = 0;
        while (broadcast_valid) begin
            for (int i = 0; i < OUTPUT_WIDTH; i++) begin
                permutated_matrix[acum] = partial_mat[i];
                acum = acum + 1;
            end
            @(posedge clk);
        end
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < WIDTH; b++) begin
                guess_val = 1;
                for (int c = 0; c < HEIGHT; c++) begin
                    if (permutated_matrix[a*HEIGHT+c] != original_matrix_clone[b*HEIGHT+c])
                        guess_val = 0;
                end
                if (guess_val)
                    guessed_permutation[a] = b;
            end
        end
        assert (guessed_permutation == dut.perm_snapshots[1])
            else $fatal(2, "Permutation is not equal to snapshotted permutation!\n");
        $finish();
    end
endmodule