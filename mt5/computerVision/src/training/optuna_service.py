
import optuna
import os
import threading
import logging
import pandas as pd
import numpy as np
import pickle
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Callable

# Import core modules
from src.database import DatabaseManager # Assuming this exists or works from context
from src.training.labeling import triple_barrier_labels
from src.training.feature_selection import FeatureSelector
from src.training.vectorized_backtester import VectorizedBacktester

logger = logging.getLogger(__name__)

class OptunaService:
    """
    Manages asynchronous Optuna optimization studies backed by PostgreSQL.
    """
    
    _instance = None

    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = OptunaService()
        return cls._instance

    def __init__(self, db_url: Optional[str] = None):
        # Use env var if not provided
        self.db_url = db_url or os.getenv('DATABASE_URL', 'postgresql://cv_agent:123@postgres:5432/cv_trading')
        if not self.db_url:
            # Fallback for local testing if needed, though strictly we want PG
            pass 
        if OptunaService._instance is None:
             OptunaService._instance = self
            
        self.active_threads: Dict[str, threading.Thread] = {}
        
    def get_storage_url(self):
        return self.db_url

    def run_optimization_async(
        self,
        study_name: str,
        objective_func: Callable,
        n_trials: int = 20,
        n_jobs: int = 1,
        sampler_name: str = "TPE"
    ):
        """
        Starts an optimization study in a background thread.
        """
        thread_name = f"optuna_{study_name}_{datetime.now().timestamp()}"
        
        def _optimize_wrapper():
            logger.info(f"Starting async optimization for {study_name}")
            try:
                # Set specific sampler
                if sampler_name == "Random":
                    sampler = optuna.samplers.RandomSampler(seed=42)
                elif sampler_name == "CmaEs":
                    sampler = optuna.samplers.CmaEsSampler(seed=42)
                else:
                    sampler = optuna.samplers.TPESampler(seed=42)

                # Initialize storage
                storage = optuna.storages.RDBStorage(url=self.db_url)
                
                # Create/Load study
                study = optuna.create_study(
                    study_name=study_name,
                    storage=storage,
                    load_if_exists=True,
                    direction='maximize',
                    sampler=sampler
                )
                
                # Run optimization
                study.optimize(objective_func, n_trials=n_trials, n_jobs=n_jobs)
                
                logger.info(f"Optimization {study_name} finished. Best value: {study.best_value}")
                
            except Exception as e:
                logger.error(f"Optimization thread failed: {e}", exc_info=True)
            finally:
                # Cleanup
                if thread_name in self.active_threads:
                    del self.active_threads[thread_name]
        
        # Create and start thread
        t = threading.Thread(target=_optimize_wrapper, name=thread_name, daemon=True)
        self.active_threads[thread_name] = t
        t.start()
        
        return thread_name

    def stop_optimization(self, thread_name: str):
        # Threads are hard to kill in Python gracefully without a stop flag inside the loop.
        # Optuna's study.optimize doesn't expose a clean stop method externally easily 
        # unless using callbacks. For now, we rely on trials finishing.
        # Future improvement: Implement a custom callback that checks a 'stop' flag in DB.
        pass

    def get_study_summary(self, study_name: str):
        try:
            storage = optuna.storages.RDBStorage(url=self.db_url)
            study = optuna.load_study(study_name=study_name, storage=storage)
            return {
                'study_name': study.study_name,
                'best_value': study.best_value if len(study.trials) > 0 else None,
                'best_params': study.best_params if len(study.trials) > 0 else None,
                'n_trials': len(study.trials),
                'datetime_start': study.trials[0].datetime_start if len(study.trials) > 0 else None
            }
        except Exception as e:
            return {'error': str(e)}

    def list_studies(self):
        try:
            # Optuna < 3.0 approach, might need adjustment for newer versions
            # But standard way is:
            storage = optuna.storages.RDBStorage(url=self.db_url)
            # Accessing internal logic or using SQL
            # storage.get_all_study_summaries() is available in newer Optuna
            return optuna.study.get_all_study_summaries(storage=storage)
        except Exception as e:
            logger.warning(f"Failed to list studies: {e}")
            return []
            
# Singleton/Utility function to get service
def get_optuna_service():
    return OptunaService()
