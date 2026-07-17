import sys
if (len(sys.argv) == 1):
    print("Usage: python " + sys.argv[0] + " matrix.txt")
    exit()
file = open(sys.argv[1], "r")
data = list(file)
lines = len(data)
len_lines = len(data[0])
transposed = ""
for a in range(0, len_lines):
    for b in range(0, lines):
        try:
            if (data[b][a] == '0' or data[b][a] == '1'):
                transposed += data[b][a]
        except:
            ()
file.close()

with open("src/matrix.svh", "w") as file_write:
    file_write.write("`define MATRIX " + str(len(transposed)) + "'b" + transposed)


