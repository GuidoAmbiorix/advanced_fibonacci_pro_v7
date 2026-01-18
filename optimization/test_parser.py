import os
import sys
sys.path.append(os.getcwd())
try:
    from lib import mq5_parser
    mt5_path = r"C:\Users\Ing Guido\Desktop\Proyectos\advanced_fibonacci_pro_v7\mt5\XAU_Pro_Agent_v2.mq5"
    
    print(f"Reading file: {mt5_path}")
    if os.path.exists(mt5_path):
        with open(mt5_path, 'r', encoding='utf-8') as f:
            content = f.read()
            if "InpFixedLots" in content:
                print("✅ 'InpFixedLots' FOUND in file content.")
            else:
                print("❌ 'InpFixedLots' NOT FOUND in file content!")
                
        params = mq5_parser.parse_mq5_inputs(mt5_path)
        found = False
        for p in params:
            if p['name'] == 'InpFixedLots':
                found = True
                print(f"✅ Parser found: {p}")
        
        if not found:
            print("❌ Parser DID NOT find InpFixedLots in params list!")
            print("dumping first 5 params detected:")
            for p in params[:5]: print(p)
            
    else:
        print("File does not exist!")

except Exception as e:
    print(f"Error: {e}")
