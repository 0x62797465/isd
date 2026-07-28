import sys
import serial

# My Python skills are not great, to summarize this does
# the gaussian elimination based off the permutation 
# matrix submitted. 

if (len(sys.argv) != 3):
    print("Usage: sage " + sys.argv[0] + " matrix.txt syndrome.txt")
    exit()
try:
    from sage.all import *
except:
    print("importing sage failed")
    print("Usage: sage " + sys.argv[0] + " matrix.txt syndrome.txt")
    exit()

F = GF(2)

file = open(sys.argv[1], "r")
data = list(file)
file.close()
height = len(data)
width = len(data[0])-1
tmp_matrix = zero_matrix(F, height, width)
for a in range(0, height):
    for b in range(0, width):
        if (data[a][b] == '0' or data[a][b] == '1'):
            tmp_matrix[a,b] = data[a][b]

file = open(sys.argv[2], "r")
data = list(file)
lines = len(data)
syndrome = zero_vector(F, lines)
for b in range(0, lines):
    try:
        if (data[b][0] == '0' or data[b][0] == '1'):
            syndrome[b] = data[b][0]
    except:
        ()
file.close()

ser_tmp = serial.Serial(
    port="/dev/ttyUSB0",
    baudrate=115200,
    bytesize=serial.EIGHTBITS,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    xonxoff=False,
    rtscts=False,
    dsrdtr=False,
    timeout=None
)

recieved = ser_tmp.read(height*16) # 16 bits, height positions

p_mat = []
for i in range (0, height):
    p_mat.append(int(recieved[i*16])*1\
        +int(recieved[i*16+1])*2\
        +int(recieved[i*16+2])*4\
        +int(recieved[i*16+3])*8\
        +int(recieved[i*16+4])*16\
        +int(recieved[i*16+5])*32\
        +int(recieved[i*16+6])*64\
        +int(recieved[i*16+7])*128\
        +int(recieved[i*16+8])*256\
        +int(recieved[i*16+9])*512\
        +int(recieved[i*16+10])*1024\
        +int(recieved[i*16+11])*2048\
        +int(recieved[i*16+12])*4096\
        +int(recieved[i*16+13])*8192\
        +int(recieved[i*16+14])*16384\
        +int(recieved[i*16+15])*32768)



found = 0
for a in range(0, width):
    found = 1
    for b in p_mat:
        if (b == a): 
            found = 0
    if found:
        p_mat.append(a)

tmp_matrix = tmp_matrix.matrix_from_columns(p_mat)
tmp_matrix = tmp_matrix.augment(syndrome)
tmp_matrix = tmp_matrix.rref()

e_error_reduced = list(tmp_matrix.column(tmp_matrix.ncols()-1)) + [0]*(width-height)
e_error = [0]*width
for i in range(width):
    e_error[p_mat[i]] = e_error_reduced[i]
e_error = vector(F, e_error)
print("Weight: " + str(e_error.hamming_weight()))
print("Error: " + str(e_error))