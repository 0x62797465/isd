#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "parser.h"

#define s_1_percent 20 // approximate percent of s_1 which we will use for the lookup

#define multithread true
//#define debug
#ifdef debug
    #define print_debug(...) printf(__VA_ARGS__)
#else
    #define print_debug(...) ((void)0)
#endif

uint32_t weight = 0;
uint8_t* parity_mat = 0;
uint8_t* permutated_mat = 0;
uint8_t* rref_aug_mat = 0;
uint8_t* syndrome = 0;
uint32_t width = 0;
uint32_t height = 0;
uint32_t s_1_size = 0;
uint32_t s_2_size = 0;


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


    for (uint16_t a = 0; a < (s_2_size); a++) {
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
    if (!c) {
        return 0;
    }
    return ( ( ( r ^ n ) >> 2 ) / c ) | r;
}

// only works when arrays are under 64 entries // I am lazy and the bitwise math would be handled by sv anyways
bool gospers_wrapper(uint8_t* array, uint16_t array_size) {
    uint64_t n = 0;
    for (uint16_t a = 0; a < array_size; a++) {
        n <<= 1;
        n |= array[array_size-1-a];
    }
    n = gospers_hack(n);

    memset(array, 0, sizeof(uint8_t)*array_size);

    if (n==0) {
        return true;
    }
    
    for (uint16_t a = 0; a < array_size; a++) {
        array[a] = n&1;
        n >>= 1;
    }

    return false;
}
    
uint8_t* global_s = 0;
uint8_t* global_e_1 = 0;
uint8_t* global_e_2 = 0;
uint16_t best_w = 0;

uint16_t global_e_1_size = 0;
uint16_t global_e_2_size = 0;

bool enumerate(uint8_t* s) {
    uint16_t enum_width = width-s_2_size;
    
    uint16_t needed_weight_e1 = (enum_width*weight)/width/2; // enum_width/width gives us the percent of weight that lives in enum_width
    uint16_t needed_weight_e2 = ((enum_width*weight)/width)%2 ? (enum_width*weight)/width/2+1 : (enum_width*weight)/width/2;
    uint16_t s_weight = weight - needed_weight_e1 - needed_weight_e2;
    
    uint16_t e1_size = (enum_width/2);
    uint16_t e2_size = enum_width%2 ? ((enum_width/2)+1) : (enum_width/2);
    global_e_1_size = e1_size; 
    global_e_2_size = e2_size;
    uint8_t *e_1 = malloc(sizeof(uint8_t)*e1_size);
    global_e_1 = malloc(sizeof(uint8_t)*e1_size);
    uint8_t *e_2 = malloc(sizeof(uint8_t)*e2_size);
    global_s = malloc(sizeof(uint8_t)*height);
    
    memset(e_1, 0, sizeof(uint8_t)*e1_size);
    memset(e_2, 0, sizeof(uint8_t)*e2_size);

    for (uint16_t a = 0; a < needed_weight_e1; a++) {
        e_1[a] = 1;
    }
    for (uint16_t a = 0; a < needed_weight_e2; a++) {
        e_2[a] = 1;
    }


    uint32_t iterations = 0;
    clock_t timer = clock();


    // memory complexity is (k!/(p!(k-p)!)), where k is size of e_1 and p is weight of e_1. This is huge and quickly
    // becomes impractical, which is why our future version will have a higher depth split 

    // this data structure holds buckets for each possible s_1 result for easy lookup, it decreases the number of exact
    // comparisons we need to do. However, in hardware it might be more memory efficient to sort instead of bucket. 
    // this will be somewhat costly, so we can possibly sort while generating? unsure
    uint8_t **e_1_list = malloc((uint64_t)(1ULL <<  s_1_size) * sizeof(int*));
    uint32_t *e_1_tails = malloc((uint64_t)(1ULL <<  s_1_size) * sizeof(uint32_t));
    uint32_t *e_1_capacities = malloc((uint64_t)(1ULL <<  s_1_size) * sizeof(uint32_t));
    
    for (uint32_t i = 0; i < (uint64_t)(1ULL <<  s_1_size); i++) {
        long pages = sysconf(_SC_AVPHYS_PAGES);
        long page_size = sysconf(_SC_PAGESIZE);
        if (pages*page_size < 1000000000ULL) { // less than a gigabyte left
            print_debug("Not enough memory for full allocation\n");
            exit(-1);
        }
        e_1_list[i] = malloc(4096 * sizeof(uint8_t));
        if (!e_1_list[i]) {
            print_debug("Malloc failed\n");
            exit(-1);
        }
        e_1_tails[i] = 0;
        e_1_capacities[i] = 4096;
    }

    uint8_t *tmp_res = malloc(height*sizeof(uint8_t));
    
    uint8_t *perm_s = malloc(height*sizeof(uint8_t));
    uint64_t tmp_s1 = 0;

    print_debug("s_1_size: %hu s_1_all: %lu\n", s_1_size, (uint64_t)(1ULL <<  s_1_size));

    uint64_t s_1_compact = 0;
    memset(perm_s, 0, height*sizeof(uint8_t));

    for (uint16_t b = 0; b < height; b++) {
        perm_s[b] ^= rref_aug_mat[(width+1)*b+width];
    }

    for (uint16_t a = 0; a < s_1_size; a++) {
        s_1_compact <<= 1ULL;
        s_1_compact |= perm_s[height-1-a];
    }
    
    print_debug("Need to generate %hu!/(%hu!%hu!)\n", e1_size, needed_weight_e1, e1_size-needed_weight_e1);

    // generate loop
    while (true) {
        iterations++;
        if (iterations%1000000 == 0) {
            iterations = 0;
            print_debug("Took %f seconds for 1,000,000 iterations\n", ((double)(clock()-timer))/CLOCKS_PER_SEC);
            timer = clock();
        }

        memset(tmp_res, 0, height*sizeof(uint8_t));
        tmp_s1 = 0;

        for (uint16_t a = 0; a < e1_size; a++) {
            if (e_1[a]) {
                for (uint16_t b = 0; b < height; b++) {
                    tmp_res[b] ^= rref_aug_mat[(width+1)*b+s_2_size+a];
                }
            }
        }

        for (uint16_t a = 0; a < s_1_size; a++) {
            tmp_s1 <<= 1ULL;
            tmp_s1 |= tmp_res[height-1-a];
        }
        //print_debug("%u\n", e_1_tails[tmp_s1]);
        
        for (uint16_t i = 0; i < e1_size; i++) {
            e_1_list[tmp_s1][e_1_tails[tmp_s1]++] = e_1[i]; 
        }
        
        for (uint16_t i = 0; i < height; i++) {
            e_1_list[tmp_s1][e_1_tails[tmp_s1]++] = tmp_res[i]; 
        }

        if ((e_1_tails[tmp_s1] + height + e1_size) >= e_1_capacities[tmp_s1]) {
            e_1_list[tmp_s1] = realloc(e_1_list[tmp_s1], e_1_capacities[tmp_s1]*2);
            long pages = sysconf(_SC_AVPHYS_PAGES);
            long page_size = sysconf(_SC_PAGESIZE);
            if (pages*page_size < 1000000000ULL) { // less than a gigabyte left
                print_debug("Terminated generation early due to low memory, continuing with search...\n");
                free(e_1);
                break;
            }
            if (!e_1_list[tmp_s1]) {
                print_debug("OOM\n");
                exit(-1);
            }
            e_1_capacities[tmp_s1] *= 2;
        }

        if (gospers_wrapper(e_1, e1_size)) {
            free(e_1);
            break;
        }
    }

    uint16_t tmp_s_weight = 0;
    // search loop
    iterations = 0;
    print_debug("Need to test %hu!/(%hu!%hu!)\n", e2_size, needed_weight_e2, e2_size-needed_weight_e2);

    while (true) {
        iterations++;
        if (iterations%1000000 == 0) {
            iterations = 0;
            print_debug("Took %f seconds for 1,000,000 iterations\n", ((double)(clock()-timer))/CLOCKS_PER_SEC);
            timer = clock();
        }

        memset(tmp_res, 0, height*sizeof(uint8_t));
        tmp_s1 = 0;

        for (uint16_t a = 0; a < e2_size; a++) {
            if (e_2[a]) {
                for (uint16_t b = 0; b < height; b++) {
                    tmp_res[b] ^= rref_aug_mat[(width+1)*b+s_2_size+e1_size+a];
                }
            }
        }

        for (uint16_t a = 0; a < s_1_size; a++) {
            tmp_s1 <<= 1ULL;
            tmp_s1 |= tmp_res[height-1-a];
        }
        //print_debug("%u\n", e_1_tails[tmp_s1]);
        
        for (uint64_t a = 0; a < e_1_tails[tmp_s1^s_1_compact]; a+=(height+e1_size)) { // does this go out of bounds? haha sometimes!
            tmp_s_weight = 0;
            for (uint16_t b = 0; b < height; b++) {
                if (b < e1_size) {
                    global_e_1[b] = e_1_list[tmp_s1^s_1_compact][b+a];
                }
                global_s[b] = perm_s[b] ^ e_1_list[tmp_s1^s_1_compact][b+e1_size+a] ^ tmp_res[b];
                tmp_s_weight += perm_s[b] ^ e_1_list[tmp_s1^s_1_compact][b+e1_size+a] ^ tmp_res[b];
            }
            if (tmp_s_weight == s_weight) {
                for (uint32_t i = 0; i < (uint64_t)(1ULL <<  s_1_size); i++) {
                    free(e_1_list[i]);
                }
                free(e_1_list);
                global_e_2 = e_2;
                free(tmp_res);
                free(perm_s);
                free(e_1_tails);
                free(e_1_capacities);
                printf("Ok\n");
                return 1;
            }
        }

        if (gospers_wrapper(e_2, e2_size)) {
            for (uint32_t i = 0; i < (uint64_t)(1ULL <<  s_1_size); i++) {
                free(e_1_list[i]);
            }
            free(e_1_list);
            free(tmp_res);
            free(e_2);
            free(perm_s);
            free(e_1_tails);
            free(e_1_capacities);
            break;
        }
    }
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 5) {
        printf("Usage: %s <matrix.txt> <syndrome.txt> <target weight> <random seed>\n", argv[0]);
        printf("Matrix identity is not infered; assumes no transposition\n");
        exit(-1);
    }

    uint16_t seed = atoi(argv[4]);
 
    o_parse(argv);
    
    s_1_size = (height*s_1_percent)/100;
    s_2_size = height-s_1_size;

    print_debug("s1 size: %hu s2 size: %hu\n", s_1_size, s_2_size);

    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    srand(seed);
    
    if (multithread) {
        for (int i = 0; i < cores; i++) {
            sleep(5);
            if (!fork()) {
                print_debug("Using seed %hu\n", seed+1+i);
                srand(seed+1+i);
                break;
            }
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
    
    for (uint16_t a = 0; a < height; a++) {
        for (uint16_t b = 0; b < width+1; b++) {
            print_debug("%hu", rref_aug_mat[a*(width+1)+b]);
        }
        print_debug('\n');
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
    
    for (uint16_t a = 0; a < s_2_size; a++) {
        final_sol[a] = global_s[a];
    }
    for (uint16_t a = 0; a < global_e_1_size; a++) {
        final_sol[s_2_size+a] = global_e_1[a];
    }
    for (uint16_t a = 0; a < global_e_2_size; a++) {
        final_sol[s_2_size+global_e_1_size+a] = global_e_2[a];
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
    free(global_e_2);
    free(unp_sol);
    putchar('\n');
} 

