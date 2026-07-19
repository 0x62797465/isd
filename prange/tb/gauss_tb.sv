`include "../src/params.svh"

module gauss_tb;
    reg clk = 0;
    reg reset = 0;
    always #10 clk = ~clk;


    reg [HEIGHT-1:0] [HEIGHT-1:0] mat_tb;
    reg [OUTPUT_WIDTH-1:0] partial_mat;
    reg [$clog2(GAUS_UNITS)-1:0] broadcast_to;
    reg broadcast_valid;

    reg done;
    reg correct;

    gauss dut (.clk(clk), .reset(reset), .partial_mat(partial_mat),
        .broadcast_to(broadcast_to), .broadcast_target(2'd2),
        .broadcast_valid(broadcast_valid), .done(done), .correct(correct));
        

    assert property (
        @(posedge clk)
        dut.col_ptr <= HEIGHT
    )
    else $fatal(2, "Column pointer out of bounds! %d", dut.col_ptr);
    
    task reset_unit();
        reset = 0;
        @(posedge clk);
        @(negedge clk);
        reset = 1;
    endtask

    task matrix_gen();
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < HEIGHT; b++) begin
                mat_tb[a][b] = $urandom()%2;
            end
        end
    endtask

    reg [$clog2(HEIGHT)-1:0] copy_ptr;
    reg [$clog2(HEIGHT)-1:0] col_ptr;

    task transfer_matrix();
        @(negedge clk);
        broadcast_to <= 2;
        broadcast_valid <= 1'b1;
        copy_ptr <= 0;
        col_ptr <= 0;
        @(posedge clk);
        while (broadcast_valid) begin
            for (int i = 0; i < OUTPUT_WIDTH; i++) begin
                partial_mat[i] <= mat_tb[col_ptr][copy_ptr+i];
            end
            if (copy_ptr+OUTPUT_WIDTH==HEIGHT) begin
                copy_ptr <= 0;
                col_ptr <= col_ptr + 1;
            end else
                copy_ptr <= copy_ptr+OUTPUT_WIDTH;
            if (col_ptr == HEIGHT)
                broadcast_valid <= 1'b0;
            @(posedge clk);
        end
    endtask

    task check_matrix_match();
        for (int a = 0; a < HEIGHT; a++) begin
            for (int b = 0; b < HEIGHT; b++) begin
                assert (mat_tb[a][b] == dut.internal_mat[b][a]) 
                    else $fatal(2, "Matrixi (plural of matrix) do not match %d %d!", a, b);
            end
        end
    endtask

    task check_weight();
        assert ($countones(dut.internal_syndrome) == dut.bitcount)
            else $fatal(2, "Internal count %d does not match real count %d\n",
                dut.bitcount, $countones(dut.internal_syndrome));
    endtask

    reg [HEIGHT-1:0] result_syndrome = 0;
    task check_solution();
        result_syndrome = '0;
        for (int a = 0; a < HEIGHT; a++) begin
            if (dut.internal_syndrome[a]) begin
                result_syndrome = result_syndrome ^ mat_tb[a];
            end
        end
        assert (result_syndrome == `SYNDROME)
            else $fatal("Syndrome %b does not equal computed %b\n", `SYNDROME, result_syndrome);
    
    endtask

    reg reached_popcount = 0;
    reg ever_reached_popcount = 0;


    initial begin
        $urandom(3);
        reset_unit();
        assert (done)
            else $fatal(2, "Not ready on reset\n");
        for (int i = 0; i < 1000; i++) begin
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
            end
            if (reached_popcount) begin
                ever_reached_popcount = 1;
                check_weight();
                check_solution();
            end
        end
        assert (ever_reached_popcount) 
            else $fatal(2, "Never reached popcount!\n");
        $finish();
    end
endmodule