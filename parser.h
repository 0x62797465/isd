#ifndef PARSER_H
#define PARSER_H
#include <stdint.h>

extern uint32_t weight;
extern uint8_t* parity_mat;
extern uint8_t* syndrome;
extern uint32_t width;
extern uint32_t height;

int o_parse(char *args[]);

#endif
