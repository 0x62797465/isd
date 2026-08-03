`include "../src/params.svh"

module perm_tb;
    reg clk = 0;
    reg reset = 0;
    reg [31:0] seed_base = '1;
    reg [GAUS_UNITS-1:0] ready;
    reg mat_bit;
    reg [$clog2(GAUS_UNITS)-1:0] broadcast_to;
    reg broadcast_valid_old;
    always #10 clk = ~clk;

    perm dut (.clk(clk), .reset(reset), .correct('0), 
        .seed_base(seed_base), .recv_ready('0), .recv_next('0),
        .ready(ready), .mat_bit(mat_bit), .broadcast_to(broadcast_to),
        .broadcast_valid_old(broadcast_valid_old), .transmit_bit());

    // basic randomness assertions
    assert property (
        @(posedge clk)
        disable iff (!reset)
        (dut.randomizer_state == 2) |-> (dut.new_seed != dut.cur_seed)
    )
    else begin
        $fatal(2, "Random seed same as previous, new: %d, prev: %d\n", 
            dut.new_seed, dut.cur_seed);
    end

    assert property (
        @(posedge clk)
        disable iff (!reset)
        (dut.randomizer_state == 2 ) |-> (dut.new_seed != '0)  
    )
    else begin
        $fatal(2, "Random seed incorrectly zero, new: %d, prev: %d\n", 
            dut.new_seed, dut.cur_seed);
    end

    // Out of bounds assertions 
    assert property (
        @(posedge clk)
        disable iff (!reset)
        (dut.perm.write_ptr < WIDTH+1)
    )
    else begin
        $fatal(2, "Out of bounds write to permutation matrix %d\n", 
            dut.perm.write_ptr);
    end

    assert property (
        @(posedge clk)
        disable iff (!reset)
        (dut.perm.read_ptr < WIDTH+1)
    )
    else begin
        $fatal(2, "Out of bounds read to permutation matrix %d\n", 
            dut.perm.read_ptr);
    end

    // Make sure readieness is asserted
    assert property (
        @(posedge clk)
        disable iff (!reset)
        ($past(dut.cycles_idle > NEEDED_CYCLES_IDLE) && $past(|ready) && dut.randomizer_state==0) |=> (dut.broadcast_valid || broadcast_valid_old) // if the past was ready, then the current is valid
    )
    else begin
        $fatal(2, "Broadcast is incorrectly low: %d\n", 
            $past(dut.new_seed));
    end

    reg [HEIGHT*(HEIGHT+1)-1:0] permutated_matrix = 'x;
    
    reg [$clog2(HEIGHT*(HEIGHT+1)):0] acum = '0;
    reg perm_invalid = 0;
    reg [HEIGHT-1:0] [WIDTH_LOG2-1:0] guessed_permutation = '0;

    localparam int words = (WIDTH)/32;
    localparam logic [WIDTH*HEIGHT-1:0] tmp_matrix = `MATRIX;
    reg [31:0] original_matrix_clone [HEIGHT-1:0] [words:0];
    reg guess_val;
    initial begin
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < WIDTH; b++) begin
                original_matrix_clone[a][b/32][b%32] = tmp_matrix[(a*WIDTH+b)];
            end
        end

        ready <= '0;

        // drive for a fixed amount of cycles; make sure permutation state is sane
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;

        /* // prints matrix state
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < WIDTH+1; b++) begin
                $write("%b", dut.original_matrix[a][b/32][b%32]);
            end
            $write("\n");
        end
        */

        while (!dut.initialized) begin
            @(posedge clk);
        end
        for (int total_test = 0; total_test < 10; total_test++) begin
            for (int i = 0; i < 10000; i++) begin
                @(posedge clk);
                if (dut.randomizer_state == 2) begin
                    for (int c = 0; c < GAUS_UNITS; c++) begin
                        for (int a = 0; a < HEIGHT; a++) begin
                            for (int b = 0; b < HEIGHT; b++) begin
                                assert (a == b || dut.perm_snapshots[c*(WIDTH+1)+a] != dut.perm_snapshots[c*(WIDTH+1)+b]) 
                                    else $fatal(2, "Impossible permutation state reached %d %d %d %d\n",
                                        a, b, dut.perm_snapshots[c*(WIDTH+1)+a], dut.perm_snapshots[c*(WIDTH+1)+b]);
                            end
                        end
                    end
                end
            end
            
            // test transfer protocal 
            ready[1] = 1'b1;
            while (!broadcast_valid_old) begin
                @(posedge clk);
            end
            ready[1] = 1'b0;
            assert(broadcast_to == 1)
                else $fatal(2, "Broadcast is to the wrong unit\n");

            acum = 0;
            while (broadcast_valid_old) begin
                permutated_matrix[acum] = mat_bit;
                acum = acum + 1;
                @(posedge clk);
            end
            for (int a = 0; a < HEIGHT; a++) begin
                for (int b = 0; b < WIDTH; b++) begin
                    guess_val = 1;
                    for (int c = 0; c < HEIGHT; c++) begin
                        if (permutated_matrix[c*(HEIGHT+1)+a] != original_matrix_clone[c][b/32][b%32])
                            guess_val = 0;
                    end
                    if (guess_val)
                        guessed_permutation[a] = b;
                end
            end

            /*
            // print permutated matrix
            for (int a = 0; a < HEIGHT; a++) begin
                for (int b = 0; b < HEIGHT+1; b++) begin
                    $write("%b", permutated_matrix[a*(HEIGHT+1)+b]);
                end
                $write("\n");
            end
            for (int a = 0; a < HEIGHT; a++) begin
                for (int b = 0; b < WIDTH+1; b++) begin
                    $write("%b", original_matrix_clone[a][b/32][b%32]);
                end
                $write("\n");
            end
            */

            for (int i = 0; i < HEIGHT; i++) begin
                assert (guessed_permutation[i] == dut.perm_snapshots[dut.perm.rename_table[1]*(WIDTH+1)+i+HEIGHT])
                    else $fatal("Permutation is not equal to snapshotted permutation! %d %d\n", guessed_permutation[i], 
                        dut.perm_snapshots[dut.perm.rename_table[1]*(WIDTH+1)+i+HEIGHT]);
            end
        end
        $finish();
    end
endmodule
