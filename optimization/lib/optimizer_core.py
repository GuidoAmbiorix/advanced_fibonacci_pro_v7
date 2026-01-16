import optuna
import os
import mt5_interface

# DB PATH
DB_PATH = "sqlite:///optimization.db"

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
        
        for p_name, p_def in param_config.items():
            if p_def['type'] == 'float':
                trial_params[p_name] = trial.suggest_float(p_name, p_def['min'], p_def['max'], step=p_def.get('step', None))
            elif p_def['type'] == 'int':
                trial_params[p_name] = trial.suggest_int(p_name, int(p_def['min']), int(p_def['max']), step=int(p_def.get('step', 1)))
            elif p_def['type'] == 'categorical':
                trial_params[p_name] = trial.suggest_categorical(p_name, p_def['choices'])
                
        # Report Trial Start
        if status_callback:
            status_callback(trial.number, n_trials, "Running", 0.0)
            
        # Files
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        ini_path = os.path.join(base_dir, "tester.ini")
        report_path = os.path.join(base_dir, f"report_{trial.number}.xml")
        
        # Create Config
        mt5_interface.create_tester_ini(
            ini_path, 
            ea_config['ea_path'], 
            ea_config['symbol'], 
            ea_config['timeframe'],
            ea_config['date_from'],
            ea_config['date_to'],
            ea_config['deposit'],
            report_path,
            trial_params
        )
        
        # Run MT5
        success = mt5_interface.run_mt5_test(ini_path, report_path)
        
        # Get Result
        profit_factor = 0.0
        if success:
            profit_factor = mt5_interface.parse_report_profit_factor(report_path)
            
        # Cleanup
        if os.path.exists(report_path):
            try:
                os.remove(report_path) 
            except: pass
            
        # Status Update
        if status_callback:
            status_callback(trial.number, n_trials, "Completed", profit_factor)
            
        return profit_factor

    # 2. Create/Load Study (SQLite Persistence)
    study = optuna.create_study(
        study_name=study_name, 
        storage=DB_PATH, 
        direction="maximize", 
        load_if_exists=True
    )
    
    # 3. Optimize with Progress Reporting
    # We wrap the loop to call callback manually if needed, 
    # but Optuna runs the loop.
    # To enable progress bar update, we rely on the callback inside 'objective'.
    
    study.optimize(objective, n_trials=n_trials)
    
    return study
