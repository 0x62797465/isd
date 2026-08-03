all: perm_tb gauss_tb prange_tb clean

perm_tb: src/perm.sv tb/perm_tb.sv
	verilator -Wno-fatal --binary --sv -Isrc src/perm.sv tb/perm_tb.sv --top-module perm_tb --Mdir build
	build/Vperm_tb


gauss_tb: src/gauss.sv tb/gauss_tb.sv
	verilator -Wno-fatal --binary --sv -Isrc src/gauss.sv tb/gauss_tb.sv --top-module gauss_tb --Mdir build
	build/Vgauss_tb

prange_tb: src/prange.sv tb/prange_tb.sv src/gauss.sv src/perm.sv src/uart.sv
	verilator -Wno-fatal --binary --sv \
		-Isrc src/prange.sv tb/prange_tb.sv src/gauss.sv src/perm.sv src/uart.sv\
		--top-module prange_tb --Mdir build
	build/Vprange_tb

clean:
	rm -rf build