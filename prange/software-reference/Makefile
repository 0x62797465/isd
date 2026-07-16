main: prange.cpp parser.cpp parser.h
	unset NIX_ENFORCE_NO_NATIVE; g++ prange.cpp parser.cpp -Ofast -march=native -flto -fgraphite-identity -floop-nest-optimize -floop-block -floop-interchange -floop-strip-mine

example: main
	./a.out matrix.txt syndrome.txt 27 0