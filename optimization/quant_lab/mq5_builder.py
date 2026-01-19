import re
import os

def transpile_lisp_to_mql5(program_str):
    """
    Translates gplearn LISP expression to MQL5 code.
    Recursive parsing logic.
    """
    # 1. Map Variables
    # These must match columns in data_miner.py AND variables in .mq5
    var_map = {
        'RSI_14': 'feat_RSI',
        'ATR_14': 'feat_ATR',
        'Momentum_10': 'feat_Mom',
        'close': 'feat_Close',
        'open': 'feat_Open',
        'SMA_20': 'iMA(NULL,0,20,0,MODE_SMA,PRICE_CLOSE)', # Direct generic call if needed, or pre-calc
        'SMA_50': 'iMA(NULL,0,50,0,MODE_SMA,PRICE_CLOSE)',
        'SMA_200': 'iMA(NULL,0,200,0,MODE_SMA,PRICE_CLOSE)'
    }
    
    # Simple Text Replacements for Variables
    for k, v in var_map.items():
        # Use word boundaries to avoid replacing substrings
        program_str = re.sub(r'\b' + k + r'\b', v, program_str)
        
    # 2. Recusively replace functions
    # Logic: Find innermost functions first (no parens inside parens)
    # But regex is hard for nested. Let's do simple text replacements for known binary ops
    # GPlearn output format is pretty standard: func(arg1, arg2)
    
    # We can use a simple stack parser or just iterative regex for standard ops
    # Let's try iterative replacement of functions
    
    ops = {
        'add': '+',
        'sub': '-',
        'mul': '*',
        'div': '/'
    }
    
    # Functions like add(A, B) -> (A + B)
    # We loop until no changes
    prev_str = ""
    while program_str != prev_str:
        prev_str = program_str
        
        # Binary Ops: op(A, B)
        # Note: A and B can be complex expressions with parens, balanced matching needed.
        # Python regex doesn't support recursive balancing easily.
        # BUT gplearn output is well formed.
        
        # Let's try a simpler approach: AST parsing or string manipulation
        # Hacky but effective for depth < 20: 
        # Replace 'add(' with 'MathAbs(' is wrong.
        # We need to change structure 'add(a, b)' to '(a + b)'
        pass

    # REWRITE: Better approach for Transpiler -> Parse the string
    # gplearn output is basically prefix notation but with commas.
    # Actually gplearn output is functional: add(a, b). 
    
    # Let's use a simple substitution for MQL5 compatible math functions
    replacements = [
         ('abs(', 'MathAbs('),
         ('log(', 'MathLog('),
         ('sqrt(', 'MathSqrt('),
         ('max(', 'MathMax('),
         ('min(', 'MathMin('),
         ('neg(', '-(')
    ]
    
    mql_code = program_str
    for old, new in replacements:
        mql_code = mql_code.replace(old, new)

    # Now handle operators that change syntax: add, sub, mul, div
    # add(a, b) -> (a + b)
    # This requires parsing arguments.
    # Since we don't have a full parser, we will do a trick:
    # 1. Define MQL functions for add, sub, mul, div!
    # 2. Paste them into the EA.
    # 3. Then the formula 'add(a,b)' IS valid MQL5 code (function call).
    
    return mql_code

def inject_formula_into_ea(formula, source_ea_path, target_ea_path):
    """
    Reads source EA, finds marker, inserts formula, saves to target.
    """
    with open(source_ea_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    marker_start = "// [[GENETIC_LOGIC_START]]"
    marker_end = "// [[GENETIC_LOGIC_END]]"
    
    if marker_start not in content:
        raise ValueError("Source EA does not have injection markers!")
        
    # Translate formula (Mapping vars only since we will use helper functions)
    mql_formula = transpile_lisp_to_mql5(formula)
    
    # Injection Code
    injection = f"""
    // [[GENETIC_LOGIC_START]]
    // 🧬 AI GENERATED FORMULA
    double geneticSignal = {mql_formula};
    // ----------------------
    // [[GENETIC_LOGIC_END]]
    """
    
    # Helper Functions (add, sub, mul, div safe versions)
    # We append these at the end of the file
    helpers = """
// 🧬 QUANT LAB HELPER FUNCTIONS
double add(double a, double b) { return a + b; }
double sub(double a, double b) { return a - b; }
double mul(double a, double b) { return a * b; }
double div(double a, double b) { return (b != 0) ? a/b : 0; }
double neg(double a) { return -a; }
    """
    
    # Replace Block
    # Regex to replace everything between markers
    pattern = re.escape(marker_start) + ".*?" + re.escape(marker_end)
    new_content = re.sub(pattern, injection, content, flags=re.DOTALL)
    
    # Append helpers if not present
    if "double add(double a, double b)" not in new_content:
        new_content += "\n" + helpers
        
    with open(target_ea_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
        
    print(f"✅ Created Genetic Bot: {target_ea_path}")
    return True
