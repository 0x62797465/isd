main: prange.c parser.c parser.h
	gcc prange.c parser.c -Ofast -march=native -flto

example: main
	./a.out matrix.txt syndrome.txt 27 0
