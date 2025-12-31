
import os

file_path = r"C:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\institutional-edge-system\frontend\src\views\BacktestView.vue"

with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()
    
# Lines are 0-indexed in python, so 560 is index 559
start_idx = 559
end_idx = 565

for i in range(start_idx, end_idx):
    print(f"Line {i+1}: {repr(lines[i])}")
