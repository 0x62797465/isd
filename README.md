## What is this?
This is a hardware implementation of Prange's algorithim, an ISD (information set decoding) algorithim. It utilizes a novel architecture optimized for high parellelism and a fast clock, outperforming modern CPUs with cheap FPGAs.

## Why?
ISD algorithims are meant to solve the SDP (syndrome decoding problem). This problem is foundational to many things, including code-based cryptography and (certain instances of) error correction. This implementation makes sense in dimensions and weights were sheer enumeration is impractical, although it is not cutting edge (see why in the future work section) it does provide good performance with very low memory complexity. 

## How?
The architecture is somewhat complex, so it is included in a separate write-up. Overall it allows one permutation unit to feed into many Gaussian elimination units. This structure is duplicated as much as hardware resources allow with a single tunable paramater (present in `src/params.svh`). The implementation of the permutation logic utilizes renaming to allow for constant swaps (using the xorshift64 algorithim) for random permutation generation along with snapshoting of in-use permutation matrixes. The Gaussian elimination units achieve RREF by recieving the permutated matrix from the permutation unit and then doing select/eliminate runs which first build a list of what rows to eliminate along with allocating the row to be used for elimination, then eliminating column by column of each row that we need to eliminate. All of this is decently pipelined, which allows for high performance.

## Benchmarks
TODO

## Usage
TODO

