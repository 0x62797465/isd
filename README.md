## What is this?
This is a hardware implementation of Prange's algorithm, an ISD (information set decoding) algorithm. It utilizes a novel architecture optimized for high parallelism and high clock speeds.

## Why?
ISD algorithms are used to solve the SDP (syndrome decoding problem). This problem is foundational to many things, including code-based cryptography and (certain instances of) error correction. This implementation makes sense in dimensions and weights where sheer enumeration is impractical, although it is not cutting edge (Prange's ISD algorithm is half a century old), it does provide good performance with very low memory complexity. 

## How?
The architecture is somewhat complex, so it is included in a separate write-up. Overall it allows one permutation unit to feed into many Gaussian elimination units. This structure is duplicated as much as hardware resources allow with a single tunable parameter (present in `src/params.svh`). The implementation of the permutation logic utilizes renaming to allow for continuous swaps (using the xorshift64 algorithm) for random permutation generation along with snapshotting of in-use permutation matrices. The Gaussian elimination units achieve RREF by receiving the permuted matrix from the permutation unit and then doing select/eliminate runs which first build a list of what rows to eliminate along with allocating the row to be used for elimination, then eliminating column by column of each row that we need to eliminate. All of this is highly pipelined, which allows for high performance.

## Benchmarks
These were all run at around half of the Fmax (50MHz) and some runs had resource underutilization. The FPGA used was a Cyclone V GX Starter Kit. For more details regarding hardware parameters, refer to the benchmarking directory.   
 
| Weight | n | Time |
|-----:|-----:|-----:|
| 27 | 200 | 31.36 s |
| 28 | 210 | 9.43 s |
| 29 | 220 | 273.30 s |
| 30 | 230 | 115.67 s |
| 31 | 240 | 23.81 s |
| 32 | 250 | 115.57 min |
| 33 | 260 | 146.04 min |
| 34 | 270 | 35.80 min |
| 35 | 280 | 785.67 min |

## Usage
Go to releases to try the optimized C++ Prange algorithm. To try the hardware implementation, use the files in `prange/utils` to generate headers which are used to generate ROM sections. Afterward, adjust `params.svh` to reflect the weight, length, and the amount of units to use (utilize the testbenches to see how optimal your parameters are and if they break anything). You may also have to change the clock in `prange.sv`, make sure to change `params.svh` accordingly. Set `prange.sv` as your top-level file, include the other sv/svh files, and synthesize. Connect the UART cable to your computer, use sage to run the `permutation2error.py` script in utils, and you will eventually see the error vector printed out. The error will be sent repeatedly, so you may connect the UART cable after the FPGA finds the error. 
 
For example files, check the `examples` directory. Note that this example and several benchmark results assume the identity matrix is before the actual matrix.
