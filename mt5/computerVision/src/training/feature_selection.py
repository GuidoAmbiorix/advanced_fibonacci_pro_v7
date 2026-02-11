import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from typing import List, Tuple

class FeatureSelector:
    """Wrapper for feature selection using Random Forest Importance."""
    
    def __init__(self, n_estimators: int = 100, random_state: int = 42):
        self.model = RandomForestClassifier(
            n_estimators=n_estimators,
            random_state=random_state,
            n_jobs=-1,
            class_weight='balanced'
        )
        self.selected_features = []
        
    def select_features(
        self,
        X: pd.DataFrame,
        y: pd.Series,
        n_features: int = 20
    ) -> List[str]:
        """
        Select top N features based on importance.
        
        Args:
            X: Feature DataFrame
            y: Target Series
            n_features: Number of features to select
            
        Returns:
            List of selected feature names
        """
        # Handle NaN
        X_clean = X.fillna(0)
        
        # Fit model
        self.model.fit(X_clean, y)
        
        # Get importances
        importances = self.model.feature_importances_
        feature_names = X.columns
        
        # Create DataFrame
        feature_imp = pd.DataFrame({
            'feature': feature_names,
            'importance': importances
        }).sort_values('importance', ascending=False)
        
        # Select top N
        self.selected_features = feature_imp.head(n_features)['feature'].tolist()
        
        return self.selected_features
        
    def get_importance_df(self, X: pd.DataFrame, y: pd.Series) -> pd.DataFrame:
        """Get full importance DataFrame."""
        X_clean = X.fillna(0)
        self.model.fit(X_clean, y)
        return pd.DataFrame({
            'feature': X.columns,
            'importance': self.model.feature_importances_
        }).sort_values('importance', ascending=False)
