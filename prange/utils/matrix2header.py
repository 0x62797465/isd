import sys
if (len(sys.argv) == 1):
    print("Usage: python " + sys.argv[0] + " matrix.txt")
    exit()
file = open(sys.argv[1], "r")
data = list(file)
file.close()
height = len(data)
width = len(data[0])

final_str = ""
for a in range(0, height):
    for b in range(0, width):
        if (data[a][b] == '0' or data[a][b] == '1'):
            final_str += data[a][b]



with open("src/matrix.svh", "w") as file_write:
    file_write.write("`define MATRIX " + str(len(final_str)) + "'b" + final_str[::-1])



