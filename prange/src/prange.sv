`include "params.svh"

module prange (
    input CLOCK_50_B5B,
    input CPU_RESET_n,
    
    output UART_TX,
    output [7:0] LEDG,
    output [7:0] LEDR
);

`define CLK CLOCK_50_B5B // will change in future
reg [TOTAL_UNITS-1:0] corr_arr;
reg [TOTAL_UNITS-1:0] transmit_bit;

reg [$clog2(TOTAL_UNITS)-1:0] recv_from;
reg recv_ready;
reg recv_next;
reg waiting;

reg [7:0] word;
reg word_ready;

reg tm_done;

genvar i;
generate
    for (i = 0; i < TOTAL_UNITS; i++) begin : gen_unit
        single_unit single_unit (.clk(`CLK), .reset(CPU_RESET_n), .seed_base(BASE_SEED+i),
            .correctness(corr_arr[i]), .transmit_bit(transmit_bit[i]), .recv_ready(recv_ready),
            .recv_next(recv_next));
    end
endgenerate

char_out char_out (.clk(`CLK), .reset(CPU_RESET_n), 
    .chr(word), .chr_ready(word_ready), .tm_ready(tm_done), 
    .UART_TX(UART_TX));

// this is optimized for small circut usage, not for speed
// since it's only really used once at the near end
reg [$clog2(10):0] delay; // loose delay to simplify transmittion
reg [$clog2(HEIGHT*16)-1:0] counter; // 16 bits per pointer
reg [$clog2(DELAY_BETWEEN_BROADCAST*CLOCK_HZ)-1:0] cycles_till_broadcast;
reg broadcasted_correct;

always_ff @(posedge `CLK or negedge CPU_RESET_n) begin
    if (!CPU_RESET_n) begin
        recv_from <= 0;
        recv_ready <= 0;
        recv_next <= 0;
        waiting <= 0;
        counter <= 0;
        broadcasted_correct <= 0;
    end else begin
        if (!broadcasted_correct) begin
            if (counter == (HEIGHT*16)) begin
                broadcasted_correct <= 1;
                cycles_till_broadcast <= DELAY_BETWEEN_BROADCAST*CLOCK_HZ;
                recv_ready <= 0;
            end
            recv_next <= 0;
            word_ready <= 0;
            // search for unit with solution
            if (!recv_ready) begin
                if (corr_arr[recv_from]) begin
                    recv_ready <= 1;
                    waiting <= 1;
                    delay <= 10;
                end else if (recv_from < TOTAL_UNITS-1)
                    recv_from <= recv_from + 1;
                else
                    recv_from <= 0;
            end
            // init delay and request bit
            else if (!delay && !waiting && tm_done && counter != (HEIGHT*16)) begin
                delay <= 10;
                recv_next <= 1;
                waiting <= 1;
                counter <= counter + 1;
            end 
            // delay
            else if (delay && waiting && tm_done)
                delay <= delay - 1;
            // recieve bit and transmit
            else if (!delay && waiting && tm_done) begin
                word <= {{7{1'b0}}, transmit_bit[recv_from]};
                word_ready <= 1;
                waiting <= '0;
            end
        end else begin
            recv_from <= 0;
            recv_ready <= 0;
            recv_next <= 0;
            waiting <= 0;
            counter <= 0;
            cycles_till_broadcast <= cycles_till_broadcast - 1;
            if (cycles_till_broadcast == 0)
                broadcasted_correct <= 0;
        end
    end
end

assign LEDG[7:0] = {8{^corr_arr}};

endmodule 

module single_unit (
    input clk,
    input reset,
    input [31:0] seed_base,
    input recv_ready,
    input recv_next,

    output reg transmit_bit,
    output reg correctness
);

reg mat_bit;
reg [GAUS_UNITS-1:0] gauss_ready;
reg [GAUS_UNITS-1:0] gauss_correct;
reg [GAUS_LOG2_SAFE-1:0] broadcast_to;
reg broadcast_valid;

perm perm (.clk(clk), .reset(reset), .seed_base(seed_base), .ready(gauss_ready),
    .correct(gauss_correct), .mat_bit(mat_bit), .broadcast_to(broadcast_to),
    .broadcast_valid_old(broadcast_valid), .transmit_bit(transmit_bit),
    .recv_ready(recv_ready), .recv_next(recv_next));

genvar i;
generate
    for (i = 0; i < GAUS_UNITS; i++) begin : gen_gauss
        gauss gauss (.clk(clk), .reset(reset), .mat_bit(mat_bit),
            .broadcast_to(broadcast_to), .broadcast_target((GAUS_LOG2_SAFE)'(i)), .broadcast_valid(broadcast_valid),
            .done(gauss_ready[i]), .correct(gauss_correct[i]));
    end
endgenerate

always_ff @(posedge clk or negedge reset) begin
    if (!reset)
        correctness <= 0;
    else 
        correctness <= |gauss_correct;
end

endmodule
