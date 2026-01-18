import optuna
import os
from lib.custom_backtester import get_backtester

# DB PATH - Use absolute path for consistent access
DATA_DIR = os.environ.get("DATA_DIR", os.path.join(os.path.dirname(__file__), "..", "data"))
DB_PATH = f"sqlite:///{os.path.abspath(os.path.join(DATA_DIR, 'optimization.db'))}"

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
            
        # Run backtest using CUSTOM BACKTESTER (MT5 Python API)
        try:
            backtester = get_backtester()
            
            result = backtester.run_backtest(
                ea_path=ea_config['ea_path'],
                symbol=ea_config['symbol'],
                timeframe=ea_config['timeframe'],
                date_from=ea_config['date_from'],
                date_to=ea_config['date_to'],
                deposit=ea_config.get('deposit', 10000),
                leverage=ea_config.get('leverage', 500),
                parameters=trial_params,
                progress_callback=lambda msg, pct: status_callback(
                    trial.number, n_trials, msg, pct / 100.0
                ) if status_callback else None
            )
            
            profit_factor = result.get('profit_factor', 0.0)
            net_profit = result.get('total_net_profit', 0.0)
            trades_count = result.get('total_trades', 0)
            max_dd = result.get('max_drawdown', 100.0)
            win_rate = result.get('win_rate', 0.0)

            # Save extra metrics
            trial.set_user_attr("net_profit", net_profit)
            trial.set_user_attr("trades", trades_count)
            trial.set_user_attr("max_drawdown", max_dd)
            trial.set_user_attr("win_rate", win_rate)
            # Save context info
            trial.set_user_attr("timeframe", ea_config['timeframe'])
            trial.set_user_attr("leverage", ea_config.get('leverage', 500))
            trial.set_user_attr("deposit", ea_config.get('deposit', 10000))
            
        except Exception as e:
            print(f"❌ Backtest error: {e}")
            profit_factor = 0.0
            max_dd = 100.0
        
        # Ensure valid Profit Factor
        if profit_factor is None or profit_factor != profit_factor: profit_factor = 0.0
        if profit_factor == float('inf') or profit_factor == float('-inf'): profit_factor = 0.0
        profit_factor = max(0.0, min(profit_factor, 1000.0))
        
        # Ensure valid Max Drawdown
        if max_dd is None or max_dd != max_dd: max_dd = 100.0
        max_dd = max(0.0, min(max_dd, 100.0))
        
        # Ensure Valid Win Rate
        if win_rate is None or win_rate != win_rate: win_rate = 0.0
        win_rate = max(0.0, min(win_rate, 100.0))
            
        return profit_factor, max_dd, win_rate

    # 2. Configure Dynamic Optimization Goal
    opt_goal = ea_config.get('optimization_goal', "Multi-Objective")
    
    directions = []
    if "Win Rate" in opt_goal and "Multi" not in opt_goal:
        directions = ["maximize"] # Just Win Rate
    elif "Profit Factor" in opt_goal and "Multi" not in opt_goal:
        directions = ["maximize"] # Just Profit
    elif "Balanced" in opt_goal:
        directions = ["maximize", "minimize"] # Profit, DD
    else:
        # Default Multi-Objective
        directions = ["maximize", "minimize", "maximize"] # Profit, DD, WinRate

    # 3. Create/Load Study
    storage = optuna.storages.RDBStorage(
        url=DB_PATH,
        engine_kwargs={"connect_args": {"timeout": 30}}
    )
    
    study = optuna.create_study(
        study_name=study_name, 
        storage=storage, 
        directions=directions, 
        load_if_exists=True
    )
    
    # Get the starting trial count (for continuing studies)
    starting_trial_count = len(study.trials)
    
    # 3. Optimize with Progress Reporting
    # Track current trial in this run (not absolute trial number)
    current_run_trial = [0]  # Use list to allow mutation in nested function
    
    def adjusted_objective(trial):
        current_run_trial[0] += 1
        pf, dd, wr = objective(trial)
        
        # Extract volume for display
        vol = "-"
        for k, v in trial.params.items():
            if "Lot" in k or "Vol" in k:
                vol = v
                break

        # Report progress
        if status_callback:
            metrics = {
                "profit_factor": pf,
                "net_profit": trial.user_attrs.get("net_profit", 0.0),
                "trades": trial.user_attrs.get("trades", 0),
                "max_drawdown": dd,
                "win_rate": wr,
                "timeframe": trial.user_attrs.get("timeframe", ""),
                "leverage": trial.user_attrs.get("leverage", 0),
                "deposit": trial.user_attrs.get("deposit", 0),
                "volume": vol
            }
            status_callback(current_run_trial[0] - 1, n_trials, "Completed", metrics)
        
        # Return based on Goal
        if "Win Rate" in opt_goal and "Multi" not in opt_goal:
            return wr
        elif "Profit Factor" in opt_goal and "Multi" not in opt_goal:
            return pf
        elif "Balanced" in opt_goal:
            return pf, dd
        else:
            return pf, dd, wr

    
    study.optimize(adjusted_objective, n_trials=n_trials)
    
    return study
