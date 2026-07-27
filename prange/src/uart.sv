// taken from previous cpu project
module char_out (
	input [7:0]        chr,
	input              chr_ready,
	input              clk,
    input              CPU_RESET_n,
	output     reg     tm_ready = 1'b1,
    output     reg     UART_TX
);

reg [9:0] baud = 10'b0;
reg [2:0] bit_ptr = 3'b0;
reg [1:0] state = 2'b0;

always @(posedge clk or negedge CPU_RESET_n) begin // putchar equivalent
    if (!CPU_RESET_n) begin
        tm_ready <= 1; // Mark as ready
        UART_TX <= 0;
		baud <= 0; // reset counter
		state <= 0;
        bit_ptr <= 0;
	end
	else begin
		if (baud == 434) begin // 50,000,000/115,200=434
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