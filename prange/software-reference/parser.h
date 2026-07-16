#ifndef PARSER_H
#define PARSER_H
#include <stdint.h>
#include <boost/dynamic_bitset.hpp>

extern uint32_t weight;
extern uint8_t* parity_mat;
extern boost::dynamic_bitset<> syndrome;
extern uint32_t width;
extern uint32_t height;

void o_parse(char *args[]);

#endif
