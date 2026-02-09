"""
Advanced Model Architectures Module

Implements ensemble models and advanced ML techniques for improved predictions.
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import VotingClassifier, StackingClassifier, RandomForestClassifier, GradientBoostingClassifier
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn.inspection import permutation_importance
from typing import Tuple, Dict, List
import pickle

try:
    from xgboost import XGBClassifier
    XGBOOST_AVAILABLE = True
except ImportError:
    XGBOOST_AVAILABLE = False
    print("⚠️ XGBoost not available. Install with: pip install xgboost")

try:
    from lightgbm import LGBMClassifier
    LIGHTGBM_AVAILABLE = True
except ImportError:
    LIGHTGBM_AVAILABLE = False
    print("⚠️ LightGBM not available. Install with: pip install lightgbm")


class EnsembleModelBuilder:
    """
    Build ensemble models combining multiple algorithms.
    """
    
    def __init__(self, random_state: int = 42):
        self.random_state = random_state
        self.scaler = StandardScaler()
    
    def build_voting_ensemble(self, X_train, y_train, voting: str = 'soft') -> VotingClassifier:
        """
        Build voting ensemble with multiple classifiers.
        
        Args:
            X_train: Training features
            y_train: Training labels
            voting: 'soft' (probability) or 'hard' (majority vote)
            
        Returns:
            Trained VotingClassifier
        """
        print("🏗️ Building Voting Ensemble...")
        
        # Base estimators
        estimators = [
            ('mlp', MLPClassifier(
                hidden_layer_sizes=(128, 64, 32),
                activation='relu',
                solver='adam',
                max_iter=100,
                early_stopping=True,
                random_state=self.random_state,
                verbose=False
            )),
            ('rf', RandomForestClassifier(
                n_estimators=100,
                max_depth=10,
                random_state=self.random_state,
                n_jobs=-1
            )),
            ('gb', GradientBoostingClassifier(
                n_estimators=100,
                max_depth=5,
                random_state=self.random_state
            ))
        ]
        
        # Add XGBoost if available
        if XGBOOST_AVAILABLE:
            estimators.append(
                ('xgb', XGBClassifier(
                    n_estimators=100,
                    max_depth=5,
                    random_state=self.random_state,
                    use_label_encoder=False,
                    eval_metric='logloss'
                ))
            )
        
        # Add LightGBM if available
        if LIGHTGBM_AVAILABLE:
            estimators.append(
                ('lgbm', LGBMClassifier(
                    n_estimators=100,
                    max_depth=5,
                    random_state=self.random_state,
                    verbose=-1
                ))
            )
        
        # Create ensemble
        ensemble = VotingClassifier(estimators=estimators, voting=voting, n_jobs=-1)
        
        print(f"  📊 Ensemble with {len(estimators)} models: {[name for name, _ in estimators]}")
        
        # Train
        ensemble.fit(X_train, y_train)
        
        print("  ✅ Voting Ensemble trained")
        
        return ensemble
    
    def build_stacking_ensemble(self, X_train, y_train) -> StackingClassifier:
        """
        Build stacking ensemble with meta-learner.
        
        Args:
            X_train: Training features
            y_train: Training labels
            
        Returns:
            Trained StackingClassifier
        """
        print("🏗️ Building Stacking Ensemble...")
        
        # Base estimators
        estimators = [
            ('rf', RandomForestClassifier(
                n_estimators=50,
                max_depth=8,
                random_state=self.random_state,
                n_jobs=-1
            )),
            ('gb', GradientBoostingClassifier(
                n_estimators=50,
                max_depth=4,
                random_state=self.random_state
            ))
        ]
        
        if XGBOOST_AVAILABLE:
            estimators.append(
                ('xgb', XGBClassifier(
                    n_estimators=50,
                    max_depth=4,
                    random_state=self.random_state,
                    use_label_encoder=False,
                    eval_metric='logloss'
                ))
            )
        
        # Meta-learner (final estimator)
        final_estimator = MLPClassifier(
            hidden_layer_sizes=(64, 32),
            max_iter=100,
            random_state=self.random_state
        )
        
        # Create stacking ensemble
        stacking = StackingClassifier(
            estimators=estimators,
            final_estimator=final_estimator,
            cv=5,
            n_jobs=-1
        )
        
        print(f"  📊 Stacking with {len(estimators)} base models + MLP meta-learner")
        
        # Train
        stacking.fit(X_train, y_train)
        
        print("  ✅ Stacking Ensemble trained")
        
        return stacking
    
    def analyze_feature_importance(self, model, X_test, y_test, 
                                   feature_names: List[str], top_n: int = 20) -> pd.DataFrame:
        """
        Analyze feature importance using permutation importance.
        
        Args:
            model: Trained model
            X_test: Test features
            y_test: Test labels
            feature_names: List of feature names
            top_n: Number of top features to return
            
        Returns:
            DataFrame with feature importance scores
        """
        print("🔍 Analyzing feature importance...")
        
        # Calculate permutation importance
        result = permutation_importance(
            model, X_test, y_test,
            n_repeats=10,
            random_state=self.random_state,
            n_jobs=-1
        )
        
        # Create DataFrame
        importance_df = pd.DataFrame({
            'feature': feature_names,
            'importance_mean': result.importances_mean,
            'importance_std': result.importances_std
        })
        
        # Sort by importance
        importance_df = importance_df.sort_values('importance_mean', ascending=False)
        
        print(f"  ✅ Top {top_n} most important features:")
        for idx, row in importance_df.head(top_n).iterrows():
            print(f"    {row['feature']}: {row['importance_mean']:.4f} ± {row['importance_std']:.4f}")
        
        return importance_df
    
    def select_top_features(self, importance_df: pd.DataFrame, 
                           threshold: float = 0.01) -> List[str]:
        """
        Select top features based on importance threshold.
        
        Args:
            importance_df: Feature importance DataFrame
            threshold: Minimum importance threshold
            
        Returns:
            List of selected feature names
        """
        selected = importance_df[importance_df['importance_mean'] > threshold]['feature'].tolist()
        
        print(f"  📊 Selected {len(selected)} features with importance > {threshold}")
        
        return selected


def train_ensemble_model(X, y, feature_names: List[str], 
                        model_type: str = 'voting') -> Tuple[object, Dict]:
    """
    Train an ensemble model with feature selection.
    
    Args:
        X: Feature matrix
        y: Labels
        feature_names: List of feature names
        model_type: 'voting' or 'stacking'
        
    Returns:
        (trained_model, metadata_dict)
    """
    print(f"\n{'='*60}")
    print(f"🚀 Training {model_type.upper()} Ensemble Model")
    print(f"{'='*60}\n")
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    
    print(f"📊 Dataset: {len(X_train)} train, {len(X_test)} test samples")
    print(f"📊 Features: {X.shape[1]}")
    print(f"📊 Class distribution: {np.bincount(y)}\n")
    
    # Scale features
    builder = EnsembleModelBuilder()
    X_train_scaled = builder.scaler.fit_transform(X_train)
    X_test_scaled = builder.scaler.transform(X_test)
    
    # Train ensemble
    if model_type == 'voting':
        model = builder.build_voting_ensemble(X_train_scaled, y_train)
    elif model_type == 'stacking':
        model = builder.build_stacking_ensemble(X_train_scaled, y_train)
    else:
        raise ValueError(f"Unknown model_type: {model_type}")
    
    # Evaluate
    train_score = model.score(X_train_scaled, y_train)
    test_score = model.score(X_test_scaled, y_test)
    
    print(f"\n📈 Performance:")
    print(f"  Train Accuracy: {train_score:.4f}")
    print(f"  Test Accuracy:  {test_score:.4f}")
    
    # Feature importance analysis
    importance_df = builder.analyze_feature_importance(
        model, X_test_scaled, y_test, feature_names, top_n=20
    )
    
    # Select top features
    top_features = builder.select_top_features(importance_df, threshold=0.001)
    
    # Prepare metadata
    metadata = {
        'model': model,
        'scaler': builder.scaler,
        'features': feature_names,
        'top_features': top_features,
        'feature_importance': importance_df.to_dict(),
        'train_accuracy': train_score,
        'test_accuracy': test_score,
        'model_type': model_type,
        'n_features': len(feature_names)
    }
    
    print(f"\n✅ {model_type.upper()} Ensemble Model training complete!\n")
    
    return model, metadata


def save_ensemble_model(model_data: Dict, filepath: str):
    """
    Save ensemble model to disk.
    
    Args:
        model_data: Model metadata dictionary
        filepath: Path to save file
    """
    with open(filepath, 'wb') as f:
        pickle.dump(model_data, f)
    
    print(f"💾 Model saved to: {filepath}")


def load_ensemble_model(filepath: str) -> Dict:
    """
    Load ensemble model from disk.
    
    Args:
        filepath: Path to model file
        
    Returns:
        Model metadata dictionary
    """
    with open(filepath, 'rb') as f:
        model_data = pickle.load(f)
    
    print(f"📂 Model loaded from: {filepath}")
    print(f"  Model type: {model_data.get('model_type', 'unknown')}")
    print(f"  Features: {model_data.get('n_features', 0)}")
    print(f"  Test accuracy: {model_data.get('test_accuracy', 0):.4f}")
    
    return model_data
