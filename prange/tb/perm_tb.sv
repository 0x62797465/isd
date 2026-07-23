`include "../src/params.svh"

module perm_tb;
    reg clk = 0;
    reg reset = 0;
    reg [31:0] seed_base = '1;
    reg [GAUS_UNITS-1:0] ready = '0;
    reg mat_bit = '0;
    reg [$clog2(GAUS_UNITS)-1:0] broadcast_to = '0;
    reg broadcast_valid_old = '0;
    always #10 clk = ~clk;

    perm dut (.clk(clk), .reset(reset), .seed_base(seed_base),
        .ready(ready), .mat_bit(mat_bit), .broadcast_to(broadcast_to),
        .broadcast_valid_old(broadcast_valid_old));

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
        (dut.perm_write_ptr < WIDTH)
    )
    else begin
        $fatal(2, "Out of bounds write to permutation matrix %d\n", 
            dut.perm_write_ptr);
    end

    assert property (
        @(posedge clk)
        disable iff (!reset)
        (dut.perm_read_ptr < WIDTH)
    )
    else begin
        $fatal(2, "Out of bounds read to permutation matrix %d\n", 
            dut.perm_read_ptr);
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
/*
    assert property (
        @(posedge clk)
        disable iff (!reset)
        $past(|ready) |=> broadcast_valid_old // if the past was ready, then the current is valid
    )
    else begin
        $fatal(2, "Broadcast is incorrectly low: %d\n", 
            $past(dut.new_seed));
    end
*/
    reg [HEIGHT*HEIGHT-1:0] permutated_matrix = 'x;
    reg [HEIGHT*HEIGHT-1:0] transposed_permutated_matrix = '0;
    
    reg [$clog2(HEIGHT*HEIGHT):0] acum = '0;
    reg perm_invalid = 0;
    reg [(WIDTH/2)-1:0] [WIDTH_LOG2-1:0] guessed_permutation = '0;

    localparam int words = (WIDTH-1)/32;
    localparam logic [WIDTH*HEIGHT-1:0] tmp_matrix = `MATRIX;
    reg [31:0] original_matrix_clone [(HEIGHT-1):0] [((WIDTH-1)/32):0];
    reg guess_val;
    initial begin
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < words+1; b++) begin
                for (int c = 0; c < 32; c++) begin
                    original_matrix_clone[a][b][c] = tmp_matrix[(a*WIDTH+b*32+c)%(WIDTH*HEIGHT-1)];
                end
            end
        end

        // drive for a fixed amount of cycles; make sure permutation state is sane
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;
        while (!dut.initialized) begin
            @(posedge clk);
        end
        for (int i = 0; i < 10000; i++) begin
            @(posedge clk);
            if (dut.randomizer_state == '0) begin
                for (int c = 0; c < GAUS_UNITS; c++) begin
                    for (int a = 0; a < ((WIDTH/2)); a++) begin
                        for (int b = 0; b < ((WIDTH/2)); b++) begin
                            if (a != b)
                                perm_invalid |= dut.perm_snapshots[c][a] == dut.perm_snapshots[c][b];
                        end
                    end
                end
                if (perm_invalid) begin
                    $fatal(2, "Impossible permutation state reached\n");
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
                    if (permutated_matrix[c*HEIGHT+a] != original_matrix_clone[c][b/32][b%32])
                        guess_val = 0;
                end
                if (guess_val) begin
                    guessed_permutation[a] = b;
                end
            end
        end

        for (int i = 0; i < HEIGHT; i++) begin
            assert (guessed_permutation[i] == dut.perm_snapshots[dut.rename_table[1]][i])
                else $fatal(2, "Permutation is not equal to snapshotted permutation! %d %d\n", guessed_permutation[i], dut.perm_snapshots[dut.rename_table[1]][i]);
        end
        $finish();
    end
endmodule