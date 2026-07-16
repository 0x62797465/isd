#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "parser.h"
#include <boost/dynamic_bitset.hpp>

uint32_t weight = 0;
uint8_t* parity_mat; // less efficient for memory but more friendly for what we do
std::vector<boost::dynamic_bitset<>> rref_aug_mat;
boost::dynamic_bitset<> syndrome;
uint32_t width = 0;
uint32_t height = 0;
uint32_t seed = 3965137938; // chosen via dice roll to prevent some wasted low-saturation itterations when seed is low
uint16_t w2 = 0;

uint32_t rrand() { // xorshift32 rng
    seed ^= seed << 13;
	seed ^= seed >> 17;
	seed ^= seed << 5;
    return seed;
}

uint8_t augment_rref() {

    // augment
    for (uint16_t a = 0; a < height; a++) {
        rref_aug_mat[a][height] = syndrome[a];
    }

    
    uint16_t w = w2;

    // attempt rref
    uint16_t swap_ptr = 0;
    bool found = false;
    bool tmp_coord;


    for (uint16_t a = 0; a < height; a++) {
        found = false;
        for (uint16_t b = a; b < height; b++) {
            if (rref_aug_mat[b][a]) {
                found = true;
                swap_ptr = b;
                break;
            }
        }
        if (!found) {
            return 1;
        }

        // vector at a = vector at swap_ptr
        std::swap(rref_aug_mat[a], rref_aug_mat[swap_ptr]);

        // actual reduction
        for (uint16_t b = 0; b < height; b++) {
            if (rref_aug_mat[b][a] && b != a) {
                if (rref_aug_mat[a][height]) { // if the bit will flip
                    if (rref_aug_mat[b][height]) { // if it will flip to zero
                        w -= 1;
                    } else { // if it will flip to one
                        w += 1;
                    }
                } 
                rref_aug_mat[b] ^= rref_aug_mat[a];
            }
        }

    }
    if (w == weight) {
        return 0;
    }
    return 1;
}


uint16_t* permutation_gen() {
    static uint16_t* permutation = 0;
    if (!permutation) {
        permutation = (uint16_t*)malloc(width*sizeof(uint16_t));    
        for (uint16_t i = 0; i < width; i++) {
            permutation[i] = i;
        }
    }

    for (uint16_t i = 0; i < (height>>1); i++) {
        std::swap(permutation[(width-height)+rrand()%height], permutation[rrand()%height]);
    }

    return permutation;
}


void apply_permutation(uint16_t* permutation) {
    for (uint16_t a = 0; a < height; a++) {
        for (uint16_t b = 0; b < height; b++) {
            __builtin_prefetch(&parity_mat[(b+1)*width+permutation[a]]);
            rref_aug_mat[b][a] = parity_mat[b*width+permutation[a]];
        }
    }
}

int main(int argc, char *argv[]) {
    
    if (argc != 5) {
        printf("Usage: %s <matrix.txt> <syndrome.txt> <target weight> <random seed>\n", argv[0]);
        printf("Matrix identity is not infered; assumes no transposition\n");
        exit(-1);
    }

    seed += atoi(argv[4]);
 
    o_parse(argv);
    
    rref_aug_mat.resize(height, boost::dynamic_bitset<>(height+1));
    w2 = syndrome.count();
    uint16_t best_weight = 0;
    long cores = sysconf(_SC_NPROCESSORS_ONLN);

    for (int i = 0; i < cores; i++) {
        if (!fork()) {
            break;
        }
        rrand();
    }
    
    uint16_t *permutation = permutation_gen();
    apply_permutation(permutation);
    
    while (augment_rref()) {
        permutation = permutation_gen();
        apply_permutation(permutation);
    }
    
    boost::dynamic_bitset<> sol(width);
    for (uint16_t a = 0; a < height; a++) {
        sol[width-1-permutation[a]] = rref_aug_mat[a][height];
    }
    std::string str;
    to_string(sol, str);
    printf("%s\n", str.c_str());
    free(permutation);
    rref_aug_mat.clear();
} 

