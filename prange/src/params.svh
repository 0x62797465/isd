`ifndef PARAMS_GAURD
`define PARAMS_GAURD
`include "matrix.svh"
// problem information
localparam int WIDTH = 200;
localparam int HEIGHT = WIDTH/2;
localparam int WIDTH_LOG2 = $clog2(WIDTH);
localparam int HEIGHT_LOG2 = $clog2(HEIGHT);
localparam int PROB_SIZE = WIDTH*HEIGHT;

// architecture config
localparam int PERMUTATE_AMOUNT = 2;
localparam int BASE_SEED = 396513798; // note, this must be non-zero
localparam int OUTPUT_CYCLES_PER_COL = 1; // height must be divisible by this
localparam int OUTPUT_WIDTH = HEIGHT/OUTPUT_CYCLES_PER_COL;
localparam int GAUS_UNITS = 4;
`endif