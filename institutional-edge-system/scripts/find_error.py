
with open('temp_logs.txt', 'r', encoding='utf-16le', errors='ignore') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "500 Internal Server Error" in line:
        print(f"Found error at line {i}")
        # Print 50 lines before
        start = max(0, i - 100)
        print("".join(lines[start:i+1]))
        break
