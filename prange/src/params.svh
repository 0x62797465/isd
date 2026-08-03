`ifndef PARAMS_GAURD
`define PARAMS_GAURD
`include "matrix.svh"
`include "syndrome.svh"

// problem information
localparam int TARGET_WEIGHT = 27;
localparam int WIDTH = 200;
localparam int HEIGHT = WIDTH/2;
localparam int WIDTH_LOG2 = $clog2(WIDTH);
localparam int HEIGHT_LOG2 = $clog2(HEIGHT);
localparam int PROB_SIZE = WIDTH*HEIGHT;

// architecture config
localparam int TOTAL_UNITS = 1;
localparam int BASE_SEED = 316513791; // note, this must be non-zero
localparam int GAUS_UNITS = 3; // per unit
localparam int GAUS_LOG2_SAFE = GAUS_UNITS-1 ? $clog2(GAUS_UNITS) : 1; 

// permutation config
localparam int NEEDED_CYCLES_IDLE = 20; // at least 5ish swaps (ranges)

// broadcast information
localparam int CLOCK_HZ = 50000000;
localparam int BAUD_RATE = 115200;
localparam int DELAY_BETWEEN_BROADCAST = 10; // in seconds (uses clock hz)

`endif
