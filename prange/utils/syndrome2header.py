import sys
# Slightly modified matrix2header.py
if (len(sys.argv) == 1):
    print("Usage: python " + sys.argv[0] + " syndrome.txt")
    exit()
file = open(sys.argv[1], "r")
data = list(file)
lines = len(data)
len_lines = len(data[0])
transposed = ""
for b in range(0, lines):
    try:
        if (data[b][0] == '0' or data[b][0] == '1'):
            transposed += data[b][0]
    except:
        ()
file.close()

with open("src/syndrome.svh", "w") as file_write:
    file_write.write("`define SYNDROME " + str(len(transposed)) + "'b" + transposed[::-1])


