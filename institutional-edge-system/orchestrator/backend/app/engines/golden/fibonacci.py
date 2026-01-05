from typing import Dict, List, Tuple

class FibonacciCalculator:
    """
    Precision Fibonacci Module.
    Calculates Retracements and Extensions based on Wave Anchors.
    """
    
    def __init__(self, config: Dict):
        self.retracement_levels = config.get('retracement_levels', [0.382, 0.5, 0.618, 0.786])
        self.extension_levels = config.get('extension_levels', [1.272, 1.618, 2.618])
        self.tolerance_pips = config.get('tolerance_pips', 5)

    def calculate_retracement_zone(self, low: float, high: float, trend: str) -> List[Dict]:
        """
        Calculate retracement levels for a given swing.
        """
        diff = high - low
        levels = []
        
        for ratio in self.retracement_levels:
            if trend == 'UP': # Pullback down
                price = high - (diff * ratio)
            else: # Pullback up
                price = low + (diff * ratio)
                
            levels.append({
                'ratio': ratio,
                'price': price,
                'type': 'RETRACEMENT'
            })
            
        return levels

    def find_active_zones(self, structure, current_price: float) -> List[Dict]:
        """
        Identify which Fib zones are currently relevant based on market structure.
        """
        if not structure.last_impulse_leg:
            return []
            
        # We only look for entries during CORRECTION phase (pullback)
        if structure.current_phase != "CORRECTION":
            return []
            
        impulse = structure.last_impulse_leg
        start_price = impulse['start'].price
        end_price = impulse['end'].price
        trend = structure.trend
        
        zones = self.calculate_retracement_zone(start_price, end_price, trend)
        
        # Filter zones relevant to current price (e.g., price is near them)
        active_zones = []
        for zone in zones:
            # Check if price is within tolerance
            # Or just return all valid zones for the core engine to check distance
            # Let's return the zone object
            zone['start_anchor'] = impulse['start'].time
            zone['end_anchor'] = impulse['end'].time
            active_zones.append(zone)
            
        return active_zones
