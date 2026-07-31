## What is this?
This is a hardware implementation of Prange's algorithim, an ISD (information set decoding) algorithim. It utilizes a novel architecture optimized for high parellelism and a fast clock, outperforming modern CPUs with cheap FPGAs.

## Why?
ISD algorithims are meant to solve the SDP (syndrome decoding problem). This problem is foundational to many things, including code-based cryptography and (certain instances of) error correction. This implementation makes sense in dimensions and weights were sheer enumeration is impractical, although it is not cutting edge (see why in the future work section) it does provide good performance with very low memory complexity. 

## How?
The architecture is somewhat complex, so it is included in a separate write-up. Overall it allows one permutation unit to feed into many Gaussian elimination units. This structure is duplicated as much as hardware resources allow with a single tunable paramater (present in `src/params.svh`). The implementation of the permutation logic utilizes renaming to allow for constant swaps (using the xorshift64 algorithim) for random permutation generation along with snapshoting of in-use permutation matrixes. The Gaussian elimination units achieve RREF by recieving the permutated matrix from the permutation unit and then doing select/eliminate runs which first build a list of what rows to eliminate along with allocating the row to be used for elimination, then eliminating column by column of each row that we need to eliminate. All of this is decently pipelined, which allows for high performance.

## Benchmarks
Every increase in weight by one is an increase in error length by ten; at wt(e)=27, the error length is 200. 
 
| Weight | Time |
|-------:|-----:|
| 27 | 31.36 s |
| 28 | 9.43 s |
| 29 | 273.30 s |
| 30 | 115.67 s |
| 31 | 23.81 s |
| 32 | 115.57 min |
| 33 | 146.04 min |
| 34 | 35.80 min |
| 35 | 785.67 min |

## Usage
Go to releases to try the optimized C++ Prange algorithm. To try the hardware implementation, use the files in `prange/utils` to generate the ROM headers. Afterward, adjust `params.svh` to reflect the weight, length, and whatever amount of hardware you want. You may also have to change the clock in `prange.sv`, make sure to change the baud rate in `UART.sv` if your MHz differs from what is included (should be 50mhz). Set `prange.sv` as your top-level file, include the other sv/svh files, and synthesize. Connect the UART capable to your computer, use sage to run the `permutation2error.py` script in utils, and you will eventually see the error vector printed out.  

