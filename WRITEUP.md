Implementation of ISD algorithms for cryptanalysis of code-based cryptosystems has largely been focused on software. Implementations using general-purpose processors have been shown to [dominate solving the syndrome decoding problem at high dimensions](https://decodingchallenge.org/syndrome/halloffame). While many modern algorithms are bottlenecked by memory speed and capacity, Prange is not. It is simple, embarrassingly parallel, and lacks the exponential memory of other algorithms like BJMM. For these reasons, it is an appropriate target for hardware-based acceleration. In this writeup, a novel hardware-based architecture for Prange's ISD algorithm is outlined. To the best of our knowledge, this is the first hardware implementation of Prange's ISD algorithm. 

---

## Preliminaires
This writeup assumes some basic knowledge of linear algebra in addition to an understanding of digital hardware design. 

### The Syndrome Decoding Problem
Given a matrix in a finite field, H with dimensions m*n, a vector in the same field, s of length m, and a weight, w, find a vector e of length n, such that He=s and the Hamming weight of e is w. The hardness of this problem comes from multiple factors, such as the weight and dimensions of the matrix. The version of the problem our architecture targets is in the finite field of two; however, the syndrome decoding problem is applicable to other finite fields. 

### Prange's ISD Algorithm
A naive approach to this problem would be to simply guess error vectors with the required weight and enumerate until a result is obtained that matches the syndrome. However, this scales extremely poorly; for every attempt, only a small subset of column vectors are guessed. Instead, we can use basic linear algebra to guess a larger subset of the vectors. To do so, we select random columns (using a permutation matrix) to construct a square matrix, then do Gaussian elimination to find a potential (permutated) error vector and check the weight. 

## Architecture
Our architecture splits Prange's algorithm into two main components: permutation and Gaussian elimination. These are done in parallel to prevent the obvious performance downside of being sequential. Additionally, generating a useful permutation and communicating the permutated matrix takes less time than Gaussian elimination, so to save space, one permutation unit is connected to multiple Gaussian elimination units. All of this is optimized to be extremely small, so many instances of these units are generated and connected to a central orchestrator. The orchestrator is responsible for finding the first valid solution of all instances and communicating it over. 

### Permutatiion
Despite the name, the permutation unit is responsible for communication with Gaussian elimination units, the orchestrator, and snapshotting permutation matrices in addition to actual permutation. 

Initially, the permutation unit has to generate a permutation matrix (which takes the form of an identity matrix since random swaps are yet to take place). We initialize a permutation matrix for each Gaussian elimination unit. In addition, there is a permutation matrix in which swaps take place to prevent overwriting in-use (potentially valid) permutation matrices. 

Every Gaussian elimination unit in a singular Prange unit is connected to the one permutation unit to indicate if a specific Gaussian elimination unit is ready for another permutated matrix. When one of these units is ready, the permutation unit assigns the current "extra" permutation matrix to the unit and makes the matrix previously assigned to the unit become the "extra" matrix. From there, it communicates the parts needed of the real matrix to construct a square matrix, stored in ROM, by accessing it with respect to the permutation matrix. Lastly, it communicates the syndrome, which gets modified by the unit, so this serves only as a minor memory-saving choice.

To prevent doing Gaussian elimination on the same matrix in the case that two or more units are done at once, a minimum amount of swapping is needed before the permutation unit decides to use the permutation matrix. This, in most cases, still allows for a near-zero delay between communication. But in the occasional case that a unit is ready before swapping has been done, it saves much more work than the amount needed to mutate the matrix. 

Once the orchestrator requests a correct permutation (which happens when it detects one of the Prange units has a high correct signal in a multi-cycle linear scan), the permutation unit stops. It then searches for which unit contains the correct permutation, then it reads it out to the orchestrator.

You may notice that we are communicating a permutation matrix in which the correct error weight was found rather than the actual recovered error. This choice was made to minimize the circuital complexity across multiple units required to reconstruct the error vector. Instead, the permutation matrix is communicated to an external processor, which does a one-time Gaussian elimination and error recovery. This only occurs one time, so the cost to overall time-to-solve is minimal. 

### Gaussian Elimination
Similar to the permutation unit, the Gaussian elimination unit also has multiple responsibilities. It receives a matrix, does Gaussian elimination, and finally checks the weight of the found vector (or terminates if the matrix is rank deficient).

Initially, the Gaussian elimination unit indicates to the permutation unit that it is ready to receive a matrix. Once the permutation unit indicates that it is sending a matrix to our Gaussian elimination unit, the Gaussian elimination unit copies the broadcasted bits to a large buffer. 

After receiving the matrix, our unit scans the first column. During this, every row with a one bit in the column has its pointer added to a list, our elimination queue. The first row with a one bit found is stored as the elimination row and allocated via a free list. Swapping, with renaming or literal memory swaps, is not necessary because the overall purpose of this unit is to invalidate or validate the permutation rather than recover the actual error vector. 

Next, the elimination unit caches the word from the row that we are using for elimination. Then, for every pointer in our elimination queue, we access the respective row's first column, XORing and writing back using the cached word. After completion, we move on to the next column, cache the word, and iterate through the list. We do this until the matrix has had the elimination completely done. 

Once elimination of the first column is done, we move on to the next. This time around, the row we allocate for elimination must be free in the free list. Otherwise, the selection is the same; we build the queue (with no regard for the free list) and jump to elimination. For elimination, we skip words before the column we are eliminating. This is because, by construction, the words will be all zero for the row we are using. 

We continue until completion or rank deficiency (which occurs when selection is unable to allocate any row). If the matrix is not rank deficient, we do a bit-count on our created error vector. If the error vector matches our required weight, we set a signal to indicate so. Otherwise, we indicate to the permutation unit that we are now ready to receive a new permutated matrix. 

### The Orchestrator
In order for us to exploit the parallelism present in this problem, we can duplicate Prange units as much as hardware allows. The only requirement being that each unit use a different random seed and that a solution is communicated once it is found (with a reasonable delay between finding and communication). Our orchestrator does both of these. 

Unique random seeds are trivial. Since the algorithm we use is xorshift, simply adding numbers to the base seed guarantees uniqueness. 

For communication, all units are searched for correct signals in a multi-cycle linear scan. Once one is found, the orchestrator broadcasts that it is ready to receive. The permutation unit receives this bit, then it scans to determine which unit has found the needed vector and uses that information to decide what snapshot to use. From there, it communicates, bit by bit, to the orchestrator, which uses the received bits to broadcast to some hardware output (in our design, UART is used).

## Results
Our implementation is highly adaptable; however, we use a Cyclone V GX Starter Kit for all of our results. This board is limited by having only 553 M10K blocks, 29,080 ALMs, and 300 DSP blocks. 

At an n of 200 and a weight of 27, 27,339 ALMs, 2,184,924 bits of BRAM, and 74 DSP blocks are utilized. The reported max clock speed is 114 MHz, with the usage of DSP blocks existing on the critical path. This is achieved with 37 Prange units, each with two Gaussian elimination units and one permutation unit. Through simulation, it is measured that a successful iteration under these parameters takes about 1341 cycles.

The following table shows some of our results with two Gaussian elimination units per permutation unit. Since Prange is a randomized search, there is heavy variance. Additionally, all of these ran at 50MHz despite having above a 110MHz timing closure.  
| Weight | n | Time | Total Prange Units | 
|-----:|-----:|-----:|-----:|
| 27 | 200 | 31.36 s | 37 |
| 28 | 210 | 9.43 s | 37 |
| 29 | 220 | 273.30 s | 37 |
| 30 | 230 | 115.67 s | 37 |
| 31 | 240 | 23.81 s | 37 |
| 32 | 250 | 115.57 min | 37 |
| 33 | 260 | 146.04 min | 23 |
| 34 | 270 | 35.80 min | 23 |
| 35 | 280 | 785.67 min | 23 |


