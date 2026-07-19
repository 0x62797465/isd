all: perm_tb 

perm_tb: src/perm.sv tb/perm_tb.sv
	vlib work
	vmap work work
	vlog -sv +incdir+src src/perm.sv tb/perm_tb.sv
	SALT_LICENSE_SERVER=~/Tools/LR-156275_License.dat vsim -suppress 12110 -quiet -c work.perm_tb -do "run -all; quit"

gauss_tb: src/gauss.sv tb/gauss_tb.sv
	vlib work
	vmap work work
	vlog -sv +incdir+src src/gauss.sv tb/gauss_tb.sv
	SALT_LICENSE_SERVER=~/Tools/LR-156275_License.dat vsim -suppress 12110 -quiet -c work.gauss_tb -do "run -all; quit"
