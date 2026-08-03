`include "../src/params.svh"

module gauss_tb;
    localparam int TEST_ITERATIONS = 200;
    reg clk = 0;
    reg reset = 0;
    always #10 clk = ~clk;

    reg [HEIGHT-1:0] [dut.WIDTH_AUG-1:0] mat_tb;
    reg mat_bit;
    reg [$clog2(GAUS_UNITS)-1:0] broadcast_to;
    reg broadcast_valid;

    reg done;
    reg correct;

    gauss dut (.clk(clk), .reset(reset), .mat_bit(mat_bit),
        .broadcast_to(broadcast_to), .broadcast_target('0),
        .broadcast_valid(broadcast_valid), .done(done), .correct(correct));


    task reset_unit();
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;
    endtask

    task matrix_gen();
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < dut.WIDTH_AUG; b++) begin
                mat_tb[a][b] = $urandom()%2;
            end
        end
    endtask

    reg [$clog2(HEIGHT)-1:0] copy_ptr;
    reg [$clog2(HEIGHT)-1:0] col_ptr;

    task transfer_matrix();
        @(negedge clk);
        broadcast_to <= 0;
        broadcast_valid <= 1'b1;
        copy_ptr <= 1;
        mat_bit <= mat_tb[0][0];
        col_ptr <= 0;
        @(posedge clk);
        while (broadcast_valid) begin
            mat_bit <= mat_tb[col_ptr][copy_ptr];
            if (copy_ptr == HEIGHT) begin
                copy_ptr <= 0;
                col_ptr <= col_ptr + 1;
            end else
                copy_ptr <= copy_ptr+1;
            if (col_ptr == dut.WIDTH_AUG)
                broadcast_valid <= 1'b0;
            @(posedge clk);
        end
    endtask

    task check_matrix_match();
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < HEIGHT; b++) begin
                assert (mat_tb[a][b] == dut.internal_mat[a*dut.WORDS+b/32][b%32]) 
                    else $fatal(2, "Matrixi (plural of matrix) do not match %d %d %h %h!", a, b, mat_tb[a][b], dut.internal_mat[b*dut.WORDS+(a/32)][a%32]);
            end
        end
    endtask

    task check_weight();
        automatic int weight = 0;
        for (int i = 0; i < HEIGHT; i++) begin
            // Selects the last column
            weight = dut.internal_mat[i*dut.WORDS+((dut.WIDTH_AUG-1)/32)][(dut.WIDTH_AUG-1)%32] + weight;
        end

        assert (weight == dut.bitcount)
            else $fatal(2, "Internal count %d does not match real count %d\n",
                dut.bitcount, weight);
    endtask

    reg [HEIGHT-1:0] result_syndrome = 0;
    task check_solution();
        automatic int recovered_weight = 0;
        automatic int original_weight = 0;    


        // essentially recovers the syndrome based off 
        // the error and permutation
        result_syndrome = '0;
        // for every element in the syndrome
        for (int a = 0; a < HEIGHT; a++) begin
            // if it's one
            if (dut.internal_mat[a*dut.WORDS+((dut.WIDTH_AUG-1)/32)][(dut.WIDTH_AUG-1)%32]) begin
                // search for the column which contains one from the identity matrix
                for (int b = 0; b < dut.WIDTH_AUG-1; b++) begin
                    if (dut.internal_mat[a*dut.WORDS+(b/32)][b%32]) begin
                        for (int c = 0; c < HEIGHT; c++) begin
                            result_syndrome[c] = result_syndrome[c] ^ mat_tb[c][b];
                        end
                    end
                end
            end
        end
        recovered_weight = $countones(result_syndrome);
        original_weight = 0;

        for (int a = 0; a < HEIGHT; a++) begin
            assert (result_syndrome[a] == mat_tb[a][dut.WIDTH_AUG-1])
                else $fatal("Syndrome (based off error) does not match real syndrome");
        end
    endtask

    reg reached_popcount = 0;
    reg ever_reached_popcount = 0;

    int n_rank_defficient = 0;

    initial begin
        automatic int silence = $urandom(2);
        reset_unit();
        assert (done)
            else $fatal(2, "Not ready on reset\n");
        for (int i = 0; i < TEST_ITERATIONS; i++) begin
            matrix_gen();
            transfer_matrix();
            check_matrix_match();
            reached_popcount = 0;
            while (!done && !correct) begin
                @(posedge clk);
                if (dut.state == dut.popcount) begin
                    reached_popcount = 1;
                end
            end
            if (correct) begin
                reset_unit();
                assert (done)
                    else $fatal(2, "Not ready on reset\n");
            end else if (reached_popcount) begin
                ever_reached_popcount = 1;
                check_weight();
                check_solution();
            end
            n_rank_defficient = n_rank_defficient + reached_popcount;
        end
        assert (ever_reached_popcount) 
            else $fatal(2, "Never reached popcount!\n");
        $write("%h/%h iterations were not rank defficient (should be around 30 percent)\n", n_rank_defficient, TEST_ITERATIONS);
        $finish();
    end
endmodule
