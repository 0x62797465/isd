`include "params.svh"

module gauss (
    input clk,
    input reset,
    input mat_bit,
    input [GAUS_LOG2_SAFE-1:0] broadcast_to,
    input [GAUS_LOG2_SAFE-1:0] broadcast_target,
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
localparam int popcount = 8; // read bit, add, check
localparam int stall = 9;
reg [$clog2(stall)-1:0] state; // assumes that stall is the last state

// matrix read/write handling
localparam WORD_SIZE = 32;
localparam WIDTH_AUG = HEIGHT+1;
localparam WORDS = WIDTH_AUG/WORD_SIZE+1;
(* ramstyle = "M10K" *) reg [WORD_SIZE-1:0] internal_mat [HEIGHT*WORDS-1:0];
struct {
    reg we;

    reg  [$clog2(WIDTH_AUG)-1:0] w_col;
    reg  [$clog2(HEIGHT)-1:0] w_row;

    reg  [$clog2(WIDTH_AUG)-1:0] r_col;
    reg  [$clog2(HEIGHT+2)-1:0] r_row; // +2 to account for select behavior

    reg [WORD_SIZE-1:0] w_buff;
    reg [WORD_SIZE-1:0] r_buff;
} mat;

wire [$clog2(WORDS)-1:0] w_col_aligned;
wire [$clog2(WORDS)-1:0] r_col_aligned;

assign w_col_aligned = mat.w_col/WORD_SIZE;
assign r_col_aligned = mat.r_col/WORD_SIZE;

wire [$clog2(HEIGHT*WORDS)-1:0] w_addr;
wire [$clog2(HEIGHT*WORDS)-1:0] r_addr;

assign w_addr = mat.w_row*WORDS+w_col_aligned;
assign r_addr = mat.r_row*WORDS+r_col_aligned;

always_ff @(posedge clk) begin
    if (mat.we) begin
        internal_mat[w_addr] <= mat.w_buff;
    end
    mat.r_buff <= internal_mat[r_addr];
end 


// elimination queue read/write handling 
(* ramstyle = "M10K" *) reg [15:0] eliminate_queue [HEIGHT-1:0];
struct {
    reg [$clog2(HEIGHT+1)-1:0] head; // write pointer
    reg [$clog2(HEIGHT+1):0] tail; // read pointer
    
    reg [15:0] buff_w; // write buff
    reg [15:0] buff_r; // read buff
    
    reg we;
} queue;

always_ff @(posedge clk) begin
    if (queue.we) begin
        eliminate_queue[queue.tail] <= queue.buff_w;
    end
    queue.buff_r <= eliminate_queue[queue.head];
end

// selection
reg [$clog2(WIDTH_AUG)-1:0] scan_col_ptr;
reg [HEIGHT-1:0] free_list; // any row not yet used for elimination
reg [$clog2(HEIGHT)-1:0] l_elim_row_ptr; // stores row that will be used for elimination
reg l_elim_ptr_found; // for early termination on rank deficient matrixes

// elimination
reg [$clog2(WIDTH_AUG)-1:0] elim_col_ptr;
reg [$clog2(HEIGHT)-1:0] elim_write_row_ptr;
reg [WORD_SIZE-1:0] word_row_cache; // cache of the current row being used for elimination

// bitcount
reg [$clog2(WIDTH_AUG)-1:0] bitcount;

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
                mat.w_row <= 0;
                mat.w_col <= 0;
                mat.r_row <= 0;
                mat.r_col <= 0;
                mat.we <= 0;
                done <= 1;

                // selection reset
                scan_col_ptr <= 0;
                free_list <= '1;
                l_elim_row_ptr <= 0;
                l_elim_ptr_found <= 0;

                if (broadcast_valid && broadcast_to == broadcast_target) begin
                    mat.we <= '1; // the first bit is received the same cycle
                    done <= '0;
                    state <= receive;
                    mat.w_buff[0] <= mat_bit;
                end
            end
            // Some tricks are used to largely abstract away the word size,
            // such as writing more than we need. However, this does not impact
            // timing (since we are limited to one bit received at a time).
            // We de-assert the write enable bit during the next stage;
            // when the state is changed we still have to commit one last write.
            receive : begin
                // note that the const modulo is optimized to wiring the lower bits
                mat.w_buff[(mat.w_col + 1) % WORD_SIZE] <= mat_bit;
                mat.w_col <= mat.w_col + 1; // only affects the actual read pointer every 32 (/word_size) iterations
                if (mat.w_col == WIDTH_AUG - 1) begin
                    if (mat.w_row == HEIGHT - 1) begin
                        mat.we <= '0;
                        mat.r_col <= '0;
                        mat.r_row <= '0;
                        state <= select_warmup;
                    end
                    mat.w_buff[0] <= mat_bit;
                    mat.w_col <= '0;
                    mat.w_row <= mat.w_row + 1; 
                end
            end
            // We set the data in cycle one, the BRAM reflects our new data onto the buffer
            // in the second cycle, and for the third cycle the buffer is viewable.
            // We mitigate a two cycle delay by setting before we jump to select; however,
            // the other cycle is unavoidable.
            select_warmup : begin
                l_elim_ptr_found <= '0;
                mat.we <= '0;
                mat.r_row <= mat.r_row + 1;
                state <= select;
                if (scan_col_ptr == HEIGHT) begin
                    mat.r_col <= WIDTH_AUG - 1;
                    mat.r_row <= 0;
                    bitcount <= 0;
                    state <= popcount_warmup;
                end
                queue.tail <= '1; // we write to queue.tail+1, so this makes it start at 0
            end
            // The three cycle delay and pipelining make the code a bit confusing,
            // but all it's doing is finding rows with bits set for the current 
            // search column, allocating the last free one, and moving onto the 
            // elimination stage.
            select : begin
                queue.head <= 0;
                queue.we <= 0;
                mat.r_row <= mat.r_row + 1;
                if (mat.r_row == HEIGHT+1) begin // a cycle after the one read two cycles ago was the last valid row 
                    if (l_elim_ptr_found) begin
                        // prevents a 4 cycle gaussian elimination warmup
                        queue.head <= 1;
                        mat.r_row <= l_elim_row_ptr;

                        elim_col_ptr <= mat.r_col;
                        mat.w_col <= mat.r_col;
                        state <= eliminate_warmup_wait;
                        free_list[l_elim_row_ptr] <= 0; // allocation
                    end else 
                        state <= uninitialized;
                end else begin
                    if (mat.r_buff[scan_col_ptr%WORD_SIZE]) begin // value from two cycles ago
                        if (free_list[mat.r_row-1] && !l_elim_ptr_found) begin // allocate first seen
                            l_elim_ptr_found <= 1;
                            l_elim_row_ptr <= mat.r_row-1;
                        end else begin
                            queue.tail <= queue.tail+1;
                            queue.buff_w <= mat.r_row-1;
                            queue.we <= 1;
                        end
                    end
                end
            end
            // A needed delay to warm up the pipeline, as we have to read the queue,
            // then read data, then xor and writeback. Since the two previous cycles
            // set the pointer for reading queue data, we can use the read buffer to
            // update the pointer for the rows. 
            eliminate_warmup_wait : begin
                queue.head <= 2;
                mat.r_row <= queue.buff_r;
                state <= eliminate_warmup_cache_write;
            end
            // We receive the needed word to xor with this cycle, we also have to 
            // maintain the pipeline. 
            eliminate_warmup_cache_write : begin
                word_row_cache <= mat.r_buff;
                queue.head <= 3;
                elim_write_row_ptr <= mat.r_row;
                mat.r_row <= queue.buff_r;
                state <= eliminate;
            end
            eliminate : begin
                mat.w_row <= elim_write_row_ptr;
                mat.w_buff <= mat.r_buff ^ word_row_cache;
                
                if (queue.head == 0 || &queue.tail) begin
                    queue.head <= 1;
                    mat.we <= 0;
                    mat.w_col <= elim_col_ptr + WORD_SIZE;

                    if (elim_col_ptr/WORD_SIZE == (WIDTH_AUG-1)/WORD_SIZE || &queue.tail) begin
                        scan_col_ptr <= scan_col_ptr + 1;
                        state <= select_warmup;
                        mat.r_col <= scan_col_ptr + 1;
                        mat.r_row <= 0;
                    end else begin
                        state <= eliminate_warmup_wait;
                        mat.r_col <= elim_col_ptr + WORD_SIZE;
                        mat.r_row <= l_elim_row_ptr;
                    end

                    elim_col_ptr <= elim_col_ptr + WORD_SIZE;
                end else begin
                    if (queue.head > queue.tail+2) begin // if what we set last cycle was out-of-bounds 
                        queue.head <= 0; // begin set up for next round
                    end else
                        queue.head <= queue.head + 1;

                    mat.we <= 1;
                    mat.r_row <= queue.buff_r;
                end
                elim_write_row_ptr <= mat.r_row;
            end
            popcount_warmup : begin
                mat.r_row <= 1;
                state <= popcount;
            end
            popcount : begin
                if (mat.r_row == HEIGHT+1) begin // if the value read a cycle ago is invalid
                    if (bitcount == TARGET_WEIGHT) begin
                        correct <= 1;
                        state <= stall;
                    end else begin
                        state <= uninitialized;
                        done <= 1;
                    end
                end else begin
                    bitcount <= bitcount + mat.r_buff[(WIDTH_AUG-1)%WORD_SIZE];
                    mat.r_row <= mat.r_row + 1;
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