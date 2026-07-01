#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
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
    srand(seed);
    
    if (argc != 4) {
        printf("Usage: %s <matrix.txt> <syndrome.txt> <target weight>\n", argv[0]);
        printf("Matrix identity is not infered; assumes no transposition\n");
        exit(-1);
    }

    o_parse(argv);

    printf("%u %u\n", width, height);
    for (int i = 0; i < width*height; i++) {
        printf("%u", parity_mat[i]);
        if (!((i+1)%width)) {
            putchar('\n');
        }
    }
    putchar('\n');

    for (int i = 0; i < height; i++) {
        printf("%u", syndrome[i]);
    }
    putchar('\n');

    printf("%u\n", weight);

    uint16_t *permutation = permutation_gen();
    for (int i = 0; i < width; i++) {
        printf("%hu ", permutation[i]);
    }
    putchar('\n');

    apply_permutation(permutation);
    for (int i = 0; i < width*height; i++) {
        printf("%hu", permutated_mat[i]);
        if (!((i+1)%width)) {
            putchar('\n');
        }
    }
    putchar('\n');

    while (augment_rref()) {
        free(permutation);
        permutation = permutation_gen();
        free(permutated_mat);
        apply_permutation(permutation);
    }
}
