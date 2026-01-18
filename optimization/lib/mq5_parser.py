import re
import os

def parse_mq5_inputs(file_path):
    """
    Parses an .mq5 file to find 'input' variables.
    Returns a list of dicts: {'name':, 'type':, 'default':, 'category':}
    """
    if not os.path.exists(file_path):
        return []

    params = []
    
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
        
    current_group = "Default"
    
    # Regex for standard inputs: input type name = value; // comment
    # captures: (group 1: type), (group 2: name), (group 3: value)
    input_pattern = re.compile(r'^\s*input\s+(\w+)\s+(\w+)\s*=\s*([^;]+);')
    
    # Regex for input groups: input group "Name"
    group_pattern = re.compile(r'^\s*input\s+group\s+"([^"]+)"')
    
    for line in lines:
        line = line.strip()
        
        # Check for Group
        group_match = group_pattern.match(line)
        if group_match:
            current_group = group_match.group(1)
            continue
            
        # Check for Input
        match = input_pattern.match(line)
        if match:
            p_type = match.group(1)
            p_name = match.group(2)
            p_val_raw = match.group(3).split('//')[0].strip() # remove comments
            
            # Clean value (handle true/false, numbers)
            p_val = p_val_raw
            p_type_clean = "string"
            
            # Type Inference Logic
            # Type Inference Logic
            if p_type == "bool":
                p_type_clean = "categorical"
                p_val = (p_val_raw.lower() == "true")
            elif p_type == "int":
                p_type_clean = "int"
                try: p_val = int(p_val_raw)
                except: continue 
            elif p_type == "double" or p_type == "float":
                p_type_clean = "float"
                try: p_val = float(p_val_raw)
                except: continue
            elif p_type == "string":
                p_type_clean = "string"
                p_val = p_val_raw.replace('"', '')
            elif "ENUM" in p_type:
                # Treat enums as int for optimization (0 to N)
                p_type_clean = "int" 
                p_val = 0 # Default assumption if we can't parse value
            
            # Include int, float, and categorical (bool)
            if p_type_clean in ["int", "float", "categorical"]:
                 params.append({
                    "name": p_name,
                    "type": p_type_clean,
                    "default": p_val,
                    "group": current_group
                })
                
    return params

def generate_optimization_config(params):
    """
    Generates intelligent optimization ranges based on default values.
    """
    config = []
    for p in params:
        default = p['default']
        p_min = default
        p_max = default
        p_step = 1
        
        if p['type'] == 'int':
            # Heuristic for ENUMS or generic INTs
            if p['name'].startswith('Inp') and ('Mode' in p['name'] or 'Type' in p['name']):
                 # Likely an ENUM
                 p_min = 0
                 p_max = 4 # Default standard enum range
                 p_step = 1
            else:
                # Standard Loop
                if default > 10:
                    p_min = int(default * 0.5)
                    p_max = int(default * 1.5)
                    p_step = max(1, int(default * 0.1))
                else:
                    p_min = max(0, default - 5)
                    p_max = default + 5
                    p_step = 1
                
        elif p['type'] == 'float':
            # Heuristic for LOTS/VOLUME
            if 'Lots' in p['name'] or 'Volume' in p['name']:
                p_min = 0.01
                p_max = 0.5 # Default conservative upper limit for checks
                p_step = 0.01
            # Standard Heuristic: +/- 50%
            elif default != 0:
                p_min = float(default * 0.5)
                p_max = float(default * 1.5)
                p_step = float(default * 0.1)
        
        # Build Config Dict
        entry = {
            "name": p['name'],
            "type": p['type'],
            "min": p_min,
            "max": p_max,
            "step": p_step,
            "group": p['group']
        }
        
        if p['type'] == 'categorical':
            entry['choices'] = [True, False] # Default boolean
            # Categorical doesn't use min/max/step in UI usually, but we keep structure
            entry['min'] = 0
            entry['max'] = 1
            entry['step'] = 1
            
        config.append(entry)
        
    return config
