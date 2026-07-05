#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "parser.h"

bool debug = true;
uint32_t weight = 0;
uint8_t* parity_mat = 0;
uint8_t* permutated_mat = 0;
uint8_t* rref_aug_mat = 0;
uint8_t* syndrome = 0;
uint32_t width = 0;
uint32_t height = 0;

void print_debug(char* printme) {
    if (debug) {
        puts(printme);
    }
}

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

uint64_t gospers_hack(const uint64_t n) {
    const uint64_t c = n & -n;
    const uint64_t r = n + c;
    return ( ( ( r ^ n ) >> 2 ) / c ) | r;
}

// only works when arrays are under 64 entries // I am lazy and the bitwise math would be handled by sv anyways
void gospers_wrapper(uint8_t* array, uint16_t array_size) {
    uint64_t n = 0;
    for (uint16_t a = 0; a < array_size; a++) {
        n <<= 1;
        n |= array[array_size-1-a];
    }
    n = gospers_hack(n);
    
    memset(array, 0, sizeof(uint8_t)*array_size);

    for (uint16_t a = 0; a < array_size; a++) {
        array[a] = n&1;
        n >>= 1;
    }
}
    
uint8_t* global_s = 0;
uint8_t* global_e_1 = 0;
uint8_t* global_e_2 = 0;


bool attempt(uint8_t *s, uint8_t *e_1, uint8_t* e_2, uint16_t e1_size, uint16_t e2_size, uint16_t s_weight) {
    uint8_t *new_s = malloc(height*sizeof(uint8_t));
    memset(new_s, 0, height);
    for (uint16_t a = 0; a < height; a++) {
        new_s[a] = s[a];
    }

    for (uint16_t a = 0; a < e1_size; a++) {
        if (e_1[a]) {
            for (uint16_t b = 0; b < height; b++) {
                new_s[b] ^= rref_aug_mat[(width+1)*b+height+a];
            }
        }
    }
    for (uint16_t a = 0; a < e2_size; a++) {
        if (e_2[a]) {
            for (uint16_t b = 0; b < height; b++) {
                new_s[b] ^= rref_aug_mat[(width+1)*b+height+a+e1_size];
            }
        }
    }
    
    global_s = new_s;
    global_e_1 = e_1;
    global_e_2 = e_2;

    uint16_t obtained_w = 0;
    for (uint16_t i = 0; i < height; i++) {
        obtained_w += new_s[i];
    }
    if (obtained_w <= s_weight) {
        return true;
    }
    free(new_s);
    return false;
}

uint16_t global_e_1_size = 0;
uint16_t global_e_2_size = 0;

bool enumerate(uint8_t* s) {
    uint16_t enum_width = width-height;
    
    uint16_t needed_weight_e1 = (enum_width*weight)/width/2; // enum_width/width gives us the percent of weight that lives in enum_width
    uint16_t needed_weight_e2 = ((enum_width*weight)/width)%2 ? (enum_width*weight)/width/2+1 : (enum_width*weight)/width/2;
    uint16_t s_weight = weight - needed_weight_e1 - needed_weight_e2;
    
    uint16_t e1_size = (enum_width/2);
    uint16_t e2_size = enum_width%2 ? ((enum_width/2)+1) : (enum_width/2);
    global_e_1_size = e1_size;
    global_e_2_size = e2_size;

    uint8_t *e_1 = malloc(sizeof(uint8_t)*e1_size);
    uint8_t *e_2 = malloc(sizeof(uint8_t)*e2_size);
    
    memset(e_1, 0, sizeof(uint8_t)*e1_size);
    memset(e_2, 0, sizeof(uint8_t)*e2_size);

    for (uint16_t a = 0; a < needed_weight_e1; a++) {
        e_1[a] = 1;
    }
    for (uint16_t a = 0; a < needed_weight_e2; a++) {
        e_2[a] = 1;
    }

    bool found = false;
    uint8_t inc_who = 0;

    while (true) {
        found = attempt(s, e_1, e_2, e1_size, e2_size, s_weight);
        if (e_2[e2_size-1]) {
            for (uint16_t a = 0; a < needed_weight_e2; a++) {
                if (e_2[e2_size-1-a] == 0) {
                    goto ok;
                }
            }
            return false;
        }
        ok:
        if (found) {
            return true;
        }
        if (inc_who) {
            gospers_wrapper(e_1, e1_size);
        } else {
            gospers_wrapper(e_2, e2_size);
        }
        inc_who ^= 1;

    }

}


int main(int argc, char *argv[]) {
    
    if (argc != 5) {
        printf("Usage: %s <matrix.txt> <syndrome.txt> <target weight> <random seed>\n", argv[0]);
        printf("Matrix identity is not infered; assumes no transposition\n");
        exit(-1);
    }

    uint16_t seed = atoi(argv[4]);
 
    o_parse(argv);
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    srand(seed);
    for (int i = 0; i < cores; i++) {
        if (!fork()) {
            srand(seed+1+i);
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
        sol[a] = rref_aug_mat[(width+1)*a+(width)];
    }
    if (!enumerate(sol)) {
        free(sol);
        free(rref_aug_mat);
        free(permutation);
        free(permutated_mat);
        goto retry;
    }
    
    uint8_t* final_sol = malloc(width*sizeof(uint8_t));
    memset(final_sol, 0, width*sizeof(uint8_t));
    
    for (uint16_t a = 0; a < height; a++) {
        final_sol[a] = global_s[a];
    }
    for (uint16_t a = 0; a < global_e_1_size; a++) {
        final_sol[height+a] = global_e_1[a];
    }
    for (uint16_t a = 0; a < global_e_2_size; a++) {
        final_sol[height+global_e_1_size+a] = global_e_2[a];
    }
    
    uint8_t* unp_sol = malloc(width*sizeof(uint8_t));
    
    for (uint16_t a = 0; a < width; a++) {
        unp_sol[permutation[a]] = final_sol[a];
    }

    for (uint8_t a = 0; a < width; a++) {
        printf("%hu", unp_sol[a]);
    }

    free(permutation);
    free(sol);
    free(final_sol);

    putchar('\n');
} 

