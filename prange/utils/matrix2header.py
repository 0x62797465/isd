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
for a in range(0, width):
    for b in range(0, height):
        if (data[b][a] == '0' or data[b][a] == '1'):
            final_str += data[b][a]



with open("src/matrix.bin", "w") as file_write:
    file_write.write(final_str[::-1])


