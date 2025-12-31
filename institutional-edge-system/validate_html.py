
import re

file_path = r"C:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\institutional-edge-system\frontend\src\views\BacktestView.vue"

def validate(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    div_balance = 0
    stack = []
    
    # Simple regex for div open/close - naive but helpful
    # Doesn't handle self-closing (div is not self-closing)
    
    # Slice lines for targeted validation to debug
    # Validate lines 480 to 600 (indices 479 to 600)
    lines_subset = lines[479:600]
    
    for i, line in enumerate(lines_subset):
        # Remove comments logic (naive)
        clean_line = re.sub(r'<!--.*?-->', '', line)
        
        open_divs = len(re.findall(r'<div\b', clean_line))
        close_divs = len(re.findall(r'</div>', clean_line))
        
        div_balance += (open_divs - close_divs)
        
        print(f"Line {480+i}: Bal {div_balance}: {line.strip()}")


    print(f"Final Div Balance: {div_balance}")
    if div_balance != 0:
        print("Error: Divs are not balanced.")

validate(file_path)
