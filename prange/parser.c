#include "parser.h"
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>

int o_parse(char *args[]) {
    FILE* file_ptr = 0;

    file_ptr = fopen(args[1], "r");
    if (!file_ptr) {
        printf("Error opening matrix\n");
        exit(-1);
    }

    // matrix parsing

    fseek(file_ptr, 0, SEEK_END);
    uint32_t size = ftell(file_ptr);
    fseek(file_ptr, 0, SEEK_SET);

    parity_mat = malloc(size * sizeof(uint8_t)); // unpacked because I'm bad at writing parsers (and sv allows bit-level arrays)

    uint32_t running_width = 0;
    uint32_t running_size = 0;
    uint8_t tmp_buf = 0;

    for (int a = 0; a < size; a++) {
        tmp_buf = fgetc(file_ptr);
        if (tmp_buf == '\n' || (tmp_buf == 255)) {
            a--;
            if (tmp_buf == 255) {
                break;
            }
            height += 1;
            if (width == 0) {
                width = running_width;
            } else if (width != running_width) {
                printf("Error parsing matrix (width did not match prev)...\n");
                exit(-1);
            }
            running_width = 0;
            continue;
        }
        running_size += 1;
        running_width += 1;
        if (tmp_buf == '1') {
            parity_mat[a] = 1;
        } else if (tmp_buf == '0') {
            parity_mat[a] = 0;
        } else {
            printf("Error parsing matrix (unkown char %c)...", tmp_buf);
            exit(-1);
        }
    }
    if (running_size != (width*height)) {
        printf("Size (%u) does not equal width (%u) times height (%u) for matrix...\n", running_size, width, height);
        exit(-1);
    }

    fclose(file_ptr);

    file_ptr = fopen(args[2], "r");
    if (!file_ptr) {
        printf("Error opening syndrome\n");
        exit(-1);
    }

    // syndome parsing
    running_width = 0;

    fseek(file_ptr, 0, SEEK_END);
    size = ftell(file_ptr);
    fseek(file_ptr, 0, SEEK_SET);

    syndrome = malloc(size*sizeof(uint8_t));

    uint8_t prev_newline = 1;

    for (int a = 0; a < size; a++) {
        tmp_buf = fgetc(file_ptr);
        if (tmp_buf == 255) {
            break;
        }
        if (tmp_buf == '\n') {
            a--;
            if (prev_newline) {
                continue;
            }
            running_width += 1;
            prev_newline = 1;
            continue;
        } else if (tmp_buf == '1') {
            syndrome[a] = 1;
        } else if (tmp_buf == '0') {
            syndrome[a] = 0;
        } else {
            printf("Error parsing syndome (unkown char %c)...\n", tmp_buf);
            exit(-1);
        }
        if (prev_newline == 0) {
            printf("Too wide syndrome (should be a column vector)\n");
            exit(-1);
        }
        prev_newline = 0;
    }

    if (running_width != height) {
        printf("Syndrome height (%u) does not equal matrix height (%u)\n", running_width, height);
        exit(-1);
    }

    fclose(file_ptr);

    weight = atoi(args[3]);
}
