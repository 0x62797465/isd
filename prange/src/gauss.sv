`include "params.svh"

module gauss (
    input clk,
    input reset,
    input mat_bit,
    input [$clog2(GAUS_UNITS)-1:0] broadcast_to,
    input [$clog2(GAUS_UNITS)-1:0] broadcast_target,
    input broadcast_valid,

    output reg done,
    output reg correct
);

// states
localparam int uninitialized = 0; // wait for receive signal
localparam int receive = 1; // write (row by row)
localparam int select_warmup = 2; // aligns row pointer reading
localparam int select = 3; // build list of all 1-bits and select a free one to use for elimination
localparam int eliminate_warmup_wait = 4; // needs a cycle for the cache read to propagate
localparam int eliminate_warmup_cache_write = 5; // writes the read cached word
localparam int eliminate = 6; // read stack, read next, xor prev & write to prev, write commit
localparam int popcount_warmup = 7; // can only look ahead one cycle, we need an additional one
localparam int popcount = 8; // read bit, add
localparam int stall = 9;
reg [$clog2(stall)-1:0] state; // assumes that stall is the last state

// matrix read/write handeling
localparam WORD_SIZE = 32;
localparam WIDTH_AUG = HEIGHT+1;
(* ramstyle = "M10K" *) reg [WORD_SIZE-1:0] internal_mat [HEIGHT-1:0] [((WIDTH_AUG)/WORD_SIZE):0];

reg mat_we;
reg [$clog2(HEIGHT)-1:0] w_row_ptr;
wire [$clog2(WIDTH_AUG/WORD_SIZE+1)-1:0] w_col_ptr;
reg [$clog2(HEIGHT+2)-1:0] r_row_ptr; // +2 to account for select behavior
wire [$clog2(WIDTH_AUG/WORD_SIZE+1)-1:0] r_col_ptr;
reg [$clog2(WIDTH_AUG)-1:0] unaligned_w_ptr;
reg [$clog2(WIDTH_AUG)-1:0] unaligned_r_ptr;

assign w_col_ptr = unaligned_w_ptr/WORD_SIZE;
assign r_col_ptr = unaligned_r_ptr/WORD_SIZE;

reg [WORD_SIZE-1:0] mat_write_buffer;
reg [WORD_SIZE-1:0] mat_read_buffer;

always_ff @(posedge clk) begin
    if (mat_we) begin
        internal_mat[w_row_ptr][w_col_ptr] <= mat_write_buffer;
    end
    mat_read_buffer <= internal_mat[r_row_ptr][r_col_ptr];
end 


// elimination queue read/write handeling 
(* ramstyle = "M10K" *) reg [15:0] eliminate_queue [HEIGHT-1:0];

reg [$clog2(HEIGHT+1)-1:0] eliminate_head; // write pointer
reg [$clog2(HEIGHT+1):0] eliminate_tail; // read pointer
reg [15:0] eliminate_buff_w; // write buff
reg [15:0] eliminate_buff_r; // read buff
reg eliminate_q_we;

always_ff @(posedge clk) begin
    if (eliminate_q_we) begin
        eliminate_queue[eliminate_tail] <= eliminate_buff_w;
    end
    eliminate_buff_r <= eliminate_queue[eliminate_head];
end

// selection
reg [$clog2(WIDTH_AUG)-1:0] scan_col_ptr;
reg [HEIGHT-1:0] free_list; // any row not yet used for elimination
reg [$clog2(HEIGHT)-1:0] l_elim_row_ptr; // stores row that will be used for elimination
reg l_elim_ptr_found; // for early termination on rank deficient matrixi

// elimination
reg [$clog2(WIDTH_AUG)-1:0] elim_col_ptr;
reg [$clog2(HEIGHT)-1:0] elim_write_row_ptr;
reg [WORD_SIZE-1:0] word_row_cache; // cache of the current row being used for elimination

// bitcount
reg [$clog2(HEIGHT+1)-1:0] bitcount;

always_ff @(posedge clk or negedge reset) begin
    if (!reset) begin
        correct <= 0;
        state <= uninitialized;
        done <= 1;
    end else begin
        case (state)
            // resets everything, waits until the permutation matrix
            // starts transmitting data before moving onto the next stage
            uninitialized : begin
                // receive/general reset
                w_row_ptr <= 0;
                unaligned_w_ptr <= 0;
                r_row_ptr <= 0;
                unaligned_r_ptr <= 0;
                mat_we <= 0;
                done <= 1;

                // selection reset
                scan_col_ptr <= 0;
                free_list <= '1;
                l_elim_row_ptr <= 0;
                l_elim_ptr_found <= 0;

                if (broadcast_valid && broadcast_to == broadcast_target) begin
                    mat_we <= '1; // the first bit is received the same cycle
                    done <= '0;
                    state <= receive;
                    mat_write_buffer[0] <= mat_bit;
                end
            end
            // Some tricks are used to largely abstract a way the word size
            // such as writing more than we need, however this does not impact
            // timing (since we are limitted to one bit received at a time).
            // We de-assert the write enable bit during the next stage because
            // when the state is changed we still have to commit one last write.
            receive : begin
                mat_write_buffer[(unaligned_w_ptr+1)%WORD_SIZE] <= mat_bit;
                unaligned_w_ptr <= unaligned_w_ptr+1; // only affects the actual read pointer every 32 iterations
                if (unaligned_w_ptr == WIDTH_AUG-1) begin
                    if (w_row_ptr == HEIGHT-1) begin
                        mat_we <= '0;
                        unaligned_r_ptr <= '0;
                        r_row_ptr <= '0;
                        state <= select_warmup;
                    end
                    mat_write_buffer[0] <= mat_bit;
                    unaligned_w_ptr <= '0;
                    w_row_ptr <= w_row_ptr + 1; 
                end
            end
            // We set the data in cycle one, the BRAM reflects our new data onto the buffer
            // in the second cycle, and for the third cycle the buffer is viewable.
            // We mitigate a two cycle delay by setting before we jump to select, however
            // the other cycle is unavoidable.
            select_warmup : begin
                l_elim_ptr_found <= '0;
                mat_we <= '0;
                r_row_ptr <= r_row_ptr + 1;
                state <= select;
                if (scan_col_ptr == HEIGHT) begin
                    unaligned_r_ptr <= WIDTH_AUG-1;
                    r_row_ptr <= 0;
                    bitcount <= 0;
                    state <= popcount_warmup;
                end
                eliminate_tail <= '1; // we write to eliminate_tail+1, so this makes it start at 0
            end
            // The three cycle delay and pipelining make the code a bit confusing,
            // but all it's doing is finding rows with bits set for the current 
            // search column, allocating the last free one, and moving onto the 
            // elimination stage.
            select : begin
                eliminate_head <= 0;
                eliminate_q_we <= 0;
                r_row_ptr <= r_row_ptr + 1;
                if (r_row_ptr == HEIGHT+1) begin // a cycle after the one read two cycles ago was the last valid row 
                    if (l_elim_ptr_found) begin
                        // prevents a 4 cycle gaussian elimination warmup
                        eliminate_head <= 1;
                        r_row_ptr <= l_elim_row_ptr;

                        elim_col_ptr <= unaligned_r_ptr;
                        unaligned_w_ptr <= unaligned_r_ptr;
                        state <= eliminate_warmup_wait;
                        free_list[l_elim_row_ptr] <= 0; // allocation
                    end else 
                        state <= uninitialized;
                end else begin
                    if (mat_read_buffer[scan_col_ptr%WORD_SIZE]) begin // value from two cycles ago
                        if (free_list[r_row_ptr-1] && !l_elim_ptr_found) begin // allocate first seen
                            l_elim_ptr_found <= 1;
                            l_elim_row_ptr <= r_row_ptr-1;
                        end else begin
                            eliminate_tail <= eliminate_tail+1;
                            eliminate_buff_w <= r_row_ptr-1;
                            eliminate_q_we <= 1;
                        end
                    end
                end
            end
            // A needed delay to warm up the pipeline, as we have to read the queue,
            // then read data, then xor and writeback. Since the two previous cycles
            // set the pointer for reading queue data, we can use the read buffer to
            // update the pointer for the rows. 
            eliminate_warmup_wait : begin
                eliminate_head <= 2;
                r_row_ptr <= eliminate_buff_r;
                state <= eliminate_warmup_cache_write;
            end
            // We recieve the needed word to xor with this cycle, we also have to 
            // maintain the pipeline. 
            eliminate_warmup_cache_write : begin
                word_row_cache <= mat_read_buffer;
                eliminate_head <= 3;
                elim_write_row_ptr <= r_row_ptr;
                r_row_ptr <= eliminate_buff_r;
                state <= eliminate;
            end
            // note to future self, use the head/tail values to prevent writing back to things that we shouldn't
            eliminate : begin
                mat_we <= 1;
                eliminate_head <= eliminate_head + 1;
                r_row_ptr <= eliminate_buff_r;
                w_row_ptr <= elim_write_row_ptr;
                mat_write_buffer <= mat_read_buffer ^ word_row_cache;
                
                if (eliminate_head > eliminate_tail+2) begin // if what we set last cycle was out-of-bounds 
                    eliminate_head <= 0; // begin set up for next round
                end
                if (eliminate_head == 0 || &eliminate_tail) begin
                    eliminate_head <= 1;
                    mat_we <= 0;
                    r_row_ptr <= l_elim_row_ptr;
                    elim_col_ptr <= elim_col_ptr + WORD_SIZE;
                    unaligned_r_ptr <= elim_col_ptr + WORD_SIZE;
                    unaligned_w_ptr <= elim_col_ptr + WORD_SIZE;

                    state <= eliminate_warmup_wait;
                    if (elim_col_ptr/WORD_SIZE == (WIDTH_AUG-1)/WORD_SIZE || &eliminate_tail) begin
                        scan_col_ptr <= scan_col_ptr + 1;
                        state <= select_warmup;
                        unaligned_r_ptr <= scan_col_ptr + 1;
                        r_row_ptr <= 0;
                    end
                end
                elim_write_row_ptr <= r_row_ptr;
            end
            popcount_warmup : begin
                r_row_ptr <= 1;
                state <= popcount;
            end
            popcount : begin
                bitcount <= bitcount + mat_read_buffer[(WIDTH_AUG-1)%WORD_SIZE];
                r_row_ptr <= r_row_ptr + 1;
                if (r_row_ptr == HEIGHT+1) begin // if the value read a cycle ago is invalid
                    if (bitcount == TARGET_WEIGHT) begin
                        correct <= 1;
                        state <= stall;
                    end else begin
                        state <= uninitialized;
                        done <= 1;
                    end
                end
            end
            stall : begin
                // does nothing
            end
            default : begin
                state <= uninitialized;
                done <= 1;
                correct <= 0;
            end
        endcase
    end
end

endmodule