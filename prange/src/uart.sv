`include "params.svh"

// taken from previous cpu project
module char_out (
	input [7:0]        chr,
	input              chr_ready,
	input              clk,
    input              reset,
	output     reg     tm_ready,
    output     reg     UART_TX
);

reg [$clog2(CLOCK_HZ/BAUD_RATE)-1:0] baud;
reg [2:0] bit_ptr;
reg [1:0] state;

always @(posedge clk or negedge reset) begin // putchar equivalent
    if (!reset) begin
        tm_ready <= 1; // Mark as ready
        UART_TX <= 1;
		baud <= 0; // reset counter
		state <= 0;
        bit_ptr <= 0;
	end
	else begin
		if (baud == CLOCK_HZ/BAUD_RATE) begin // 50,000,000/115,200=434
			baud <= 0;
			case (state)
				2'b00 : begin // lower signal to signal a start of a byte
					UART_TX <= 0;
					state <= state + 1;
				end
				2'b01 : begin
					if (bit_ptr == 3'b111) // end of byte
						state <= state + 1;	
					UART_TX <= chr[bit_ptr]; // put bit in
					bit_ptr <= bit_ptr + 1;
				end
				2'b10 : begin
					UART_TX <= 1; // mark byte as done
					state <= 0;
					tm_ready <= 1;
				end
			endcase
		end else if (tm_ready && chr_ready) begin
			baud <= 0;
			tm_ready <= 0; // mark as in use
		end else if (!tm_ready)
			baud <= baud + 1;
	end
end
endmodule