#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "parser.h"

uint32_t weight = 0;
uint8_t* parity_mat = 0;
uint8_t* permutated_mat = 0;
uint8_t* rref_aug_mat = 0;
uint8_t* syndrome = 0;
uint32_t width = 0;
uint32_t height = 0;

uint8_t augment_rref() {
    rref_aug_mat = malloc((width+1)*height);

    // augment
    for (uint16_t a = 0; a < height; a++) {
        for (uint16_t b = 0; b < width; b++) {
            rref_aug_mat[a*(width+1)+b] = permutated_mat[a*width+b]; 
        }
        rref_aug_mat[a*(width+1)+width] = syndrome[a];
    }

    // attempt rref
    uint16_t swap_ptr;
    bool found = false;
    uint8_t tmp_coord;


    for (uint16_t a = 0; a < height; a++) {
        found = false;
        for (uint16_t b = a; b < height; b++) {
            if (rref_aug_mat[b*(width+1)+a]) {
                found = true;
                swap_ptr = b;
                break;
            }
        }
        if (!found) {
            return 1;
        }

        // vector at a = vector at swap_ptr
        for (uint16_t b = 0; b < width+1; b++) {
            tmp_coord = rref_aug_mat[a*(width+1)+b];
            rref_aug_mat[a*(width+1)+b] = rref_aug_mat[swap_ptr*(width+1)+b];
            rref_aug_mat[swap_ptr*(width+1)+b] = tmp_coord; 
        }

        // actual reduction
        for (uint16_t b = 0; b < height; b++) {
            if (rref_aug_mat[b*(width+1)+a] && b != a) {
                for (uint16_t c = 0; c < width+1; c++) {
                    rref_aug_mat[b*(width+1)+c] ^= rref_aug_mat[a*(width+1)+c]; 
                }       
            }
        }

    }

    return 0;
}

uint16_t* permutation_gen() {
    uint16_t* permutation = 0;
    permutation = malloc(width*sizeof(uint16_t));
    for (uint16_t i = 0; i < width; i++) {
        permutation[i] = i;
    }

    uint16_t swap_buff;
    uint16_t rand_buff;

    for (uint16_t i = 0; i < width; i++) {
        rand_buff = rand()%width;
        swap_buff = permutation[i];
        permutation[i] = permutation[rand_buff];
        permutation[rand_buff] = swap_buff;
    }

    return permutation;
}

void apply_permutation(uint16_t* permutation) {
    permutated_mat = malloc(height*width*sizeof(uint8_t));
    for (int a = 0; a < width; a++) {
        for (int b = 0; b < height; b++) {
            permutated_mat[b*width+a] = parity_mat[b*width+permutation[a]];
        }
    }
}

int main(int argc, char *argv[]) {
    uint16_t seed = time(NULL);
    
    if (argc != 4) {
        printf("Usage: %s <matrix.txt> <syndrome.txt> <target weight>\n", argv[0]);
        printf("Matrix identity is not infered; assumes no transposition\n");
        exit(-1);
    }

    o_parse(argv);
    uint16_t best_weight = 0;
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    for (int i = 0; i < cores; i++) {
        srand(seed+i);
        if (!fork()) {
            break;
        }
    }
    retry:
    uint16_t *permutation = permutation_gen();
    apply_permutation(permutation);

    while (augment_rref()) {
        free(rref_aug_mat);
        free(permutation);
        permutation = permutation_gen();
        free(permutated_mat);
        apply_permutation(permutation);
    }
    
    uint8_t* sol = malloc(width*sizeof(uint8_t));
    memset(sol, 0, width*sizeof(uint8_t));
    for (uint16_t a = 0; a < height; a++) {
        sol[permutation[a]] = rref_aug_mat[(width+1)*a+(width)];
    }
    uint16_t targ_weight = 0;
    for (uint16_t a = 0; a < width; a++) {
        targ_weight += sol[a];
    }
    if (!best_weight || best_weight > targ_weight) {
        printf("%hu\n", targ_weight);
        best_weight = targ_weight;
    }
    if (weight <= targ_weight) {
        free(rref_aug_mat);
        free(permutation);
        free(permutated_mat);
        goto retry;
    }
    putchar('\n');
    for (uint8_t a = 0; a < width; a++) {
        printf("%hu", sol[a]);
    }
    putchar('\n');
} 

