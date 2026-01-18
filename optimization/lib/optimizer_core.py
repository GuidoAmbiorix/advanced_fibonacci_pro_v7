import optuna
import os
import mt5_interface

# DB PATH - Use DATA_DIR if available (Docker) or current dir (local)
DATA_DIR = os.environ.get("DATA_DIR", ".")
DB_PATH = f"sqlite:///{os.path.join(DATA_DIR, 'optimization.db')}"

def run_optimization_task(study_name, n_trials, param_config, ea_config, status_callback=None):
    """
    Core Optimization Loop
    param_config: dict of {param_name: {type: 'float'/'int'/'cat', min: x, max: y, step: z}}
    ea_config: dict of {ea_path, symbol, timeframe, dates...}
    """
    
    # 1. Define Objective with Dynamic Params
    def objective(trial):
        # Build Params for this specific trial
        trial_params = {}
        used_names = set()  # Track used parameter names to avoid duplicates
        
        for p_name, p_def in param_config.items():
            # Aggressively truncate parameter names (SQLite has limits with many params)
            # Use max 100 chars to be safe with 27+ parameters
            safe_p_name = p_name[:100] if len(p_name) > 100 else p_name
            
            # Ensure uniqueness after truncation
            original_safe_name = safe_p_name
            counter = 1
            while safe_p_name in used_names:
                # Add suffix to make it unique
                suffix = f"_{counter}"
                safe_p_name = original_safe_name[:100-len(suffix)] + suffix
                counter += 1
            used_names.add(safe_p_name)
            
            try:
                if p_def['type'] == 'float':
                    trial_params[p_name] = trial.suggest_float(safe_p_name, p_def['min'], p_def['max'], step=p_def.get('step', None))
                elif p_def['type'] == 'int':
                    trial_params[p_name] = trial.suggest_int(safe_p_name, int(p_def['min']), int(p_def['max']), step=int(p_def.get('step', 1)))
                elif p_def['type'] == 'categorical':
                    trial_params[p_name] = trial.suggest_categorical(safe_p_name, p_def['choices'])
            except Exception as e:
                # If parameter suggestion fails, skip it and log
                print(f"Warning: Failed to add parameter {safe_p_name}: {e}")
                continue
                
        # Report Trial Start
        if status_callback:
            status_callback(trial.number, n_trials, "Running", 0.0)
            
        # Run MT5 via remote API (no local files needed)
        success = mt5_interface.run_mt5_test(
            ini_path=None,  # Not used with remote API
            report_path=None,  # Not used with remote API
            ea_path=ea_config['ea_path'],
            symbol=ea_config['symbol'],
            timeframe=ea_config['timeframe'],
            date_from=ea_config['date_from'],
            date_to=ea_config['date_to'],
            deposit=ea_config['deposit'],
            params=trial_params
        )
        
        # Get Result from the API
        profit_factor = 0.0
        if success:
            profit_factor = mt5_interface.get_last_profit_factor()
        
        # Ensure we always return a valid float (Optuna doesn't like None, NaN, or Inf)
        if profit_factor is None or profit_factor != profit_factor:  # Check for None or NaN
            profit_factor = 0.0
        if profit_factor == float('inf') or profit_factor == float('-inf'):
            profit_factor = 0.0
        # Clamp to reasonable range
        profit_factor = max(0.0, min(profit_factor, 1000.0))
            
        # Status Update
        if status_callback:
            status_callback(trial.number, n_trials, "Completed", profit_factor)
            
        return float(profit_factor)  # Ensure it's definitely a float

    # 2. Create/Load Study (SQLite Persistence with increased limits)
    # Configure storage with larger limits for many parameters
    storage = optuna.storages.RDBStorage(
        url=DB_PATH,
        engine_kwargs={"connect_args": {"timeout": 30}}
    )
    
    study = optuna.create_study(
        study_name=study_name, 
        storage=storage, 
        direction="maximize", 
        load_if_exists=True
    )
    
    # Get the starting trial count (for continuing studies)
    starting_trial_count = len(study.trials)
    
    # 3. Optimize with Progress Reporting
    # Adjust counter to show current run progress, not absolute trial numbers
    def adjusted_objective(trial):
        result = objective(trial)
        # Override the callback with corrected trial numbers
        if status_callback:
            current_trial_in_run = trial.number - starting_trial_count + 1
            status_callback(current_trial_in_run - 1, n_trials, "Completed", result if result else 0.0)
        return result
    
    study.optimize(adjusted_objective, n_trials=n_trials)
    
    return study
