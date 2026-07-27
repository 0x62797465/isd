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
localparam int TOTAL_UNITS = 36;
localparam int BASE_SEED = 316513791; // note, this must be non-zero
localparam int GAUS_UNITS = 2; // per unit

// permutation config
localparam int NEEDED_CYCLES_IDLE = 20; // at least 5ish swaps (ranges)

`endif
