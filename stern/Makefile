main: stern.c parser.c parser.h
	gcc stern.c parser.c -Ofast -march=native -flto

example: main
	./a.out matrix.txt syndrome.txt 23 1
