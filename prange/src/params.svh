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

// DO NOT CHANGE EXCEPT FOR SEED; HIGHLY INSTABLE DUE TO CHANGING ARCHITECTURE
// architecture config
localparam int PERMUTATE_AMOUNT = 2;
localparam int BASE_SEED = 316513791; // note, this must be non-zero
localparam int GAUS_UNITS = 2;

// gaus config
localparam int SEARCH_PER_CYCLE = 1; // amount of vectors to search for during the swap part of gaussian elimination
localparam int ELIMINATE_PER_CYCLE = 1; // more = less time more circutry; less = more time less circutry
localparam int BITS_COUNTED_PER_CYCLE = 1;

`endif