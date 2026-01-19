export const SYMBOL_PRESETS = {
  'GBPJPY': { 
    name: 'GBP/JPY', emoji: '😈', volatility: 'HIGH',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5, 
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'The Beast 🔥 High volatility, strong trends' 
  },
  'EURUSD': { 
    name: 'EUR/USD', emoji: '💶', volatility: 'LOW',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Most liquid - Tight stops, trade both directions' 
  },
  'XAUUSD': { 
    name: 'XAU/USD', emoji: '🥇', volatility: 'EXTREME',
    engine_type: 'XAU_PRO',
    timeframe: 'M15', tsl_mode: 'ATR',
    risk_percent: 0.5, tp_ratio: 2.0, sl_atr_multiplier: 1.4,
    rsi_period: 14, rsi_overbought: 60, rsi_oversold: 40,
    min_confluence: 5, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    zigzag_lookback: 12,
    macd_fast: 6, macd_slow: 18, macd_signal: 9,
    session_mode: 'BOTH_KZ',
    enable_order_blocks: true, ob_lookback: 20,
    enable_liquidity_sweep: true, sweep_lookback: 10,
    enable_fvg: true, fvg_min_size_atr: 0.5,
    direction: 'BOTH', 
    description: 'Gold 🥇 v4.1 SMC (Sweep+Zone, ~70% WR)' 
  },
  'USDJPY': { 
    name: 'USD/JPY', emoji: '🇯🇵', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Smooth trends - Tight SL, let profits run' 
  },
  'AUDJPY': { 
    name: 'AUD/JPY', emoji: '🦘', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: false, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Carry trade pair - Positive swap on long' 
  },
  'NZDJPY': { 
    name: 'NZD/JPY', emoji: '🥝', volatility: 'MEDIUM',
    timeframe: 'M15', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.5, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: false, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Carry trade pair - Positive swap on long' 
  },
  'EURCHF': { 
    name: 'EUR/CHF', emoji: '🇨🇭', volatility: 'LOW',
    timeframe: 'M15', tsl_mode: 'OFF',
    risk_percent: 1.5, tp_ratio: 1.5, sl_atr_multiplier: 0.75, 
    rsi_period: 14, rsi_overbought: 65, rsi_oversold: 35, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: false, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Range Trading ↔️ Both directions - Low volatility' 
  },
  'EURGBP': { 
    name: 'EUR/GBP', emoji: '💶💷', volatility: 'LOW',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.0, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Channel 💶💷 Range trading - Low volatility' 
  },
  'EURJPY': { 
    name: 'EUR/JPY', emoji: '🇪🇺🇯🇵', volatility: 'HIGH',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 0.75, tp_ratio: 2.0, sl_atr_multiplier: 1.5,
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'EUR/JPY 🔥 High volatility cross - Fast moves' 
  },
  'USDCHF': { 
    name: 'USD/CHF', emoji: '🇺🇸🇨🇭', volatility: 'LOW',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.0,
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'USD/CHF ↔️ Range trading - Mirrors EURUSD' 
  },
  'AUDUSD': { 
    name: 'AUD/USD', emoji: '🦘', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5,
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'AUD/USD 🦘 Commodity pair - Low correlation with majors' 
  },
  'USDCAD': { 
    name: 'USD/CAD', emoji: '🍁', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'TIERED',
    risk_percent: 1.0, tp_ratio: 2.0, sl_atr_multiplier: 1.5,
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'USD/CAD 🍁 Oil-linked - Independent of European pairs' 
  },
  '#BTCUSD': { 
    name: 'Bitcoin', emoji: '₿', volatility: 'EXTREME',
    timeframe: 'M15', tsl_mode: 'TIERED',
    risk_percent: 0.5, tp_ratio: 2.0, sl_atr_multiplier: 2.0,
    rsi_period: 9, rsi_overbought: 75, rsi_oversold: 25, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Bitcoin ₿ Extreme volatility - Wide stops, fast moves' 
  },
  'GBPUSD': { 
    name: 'GBP/USD', emoji: '💷', volatility: 'MEDIUM',
    timeframe: 'M5', tsl_mode: 'ATR',
    risk_percent: 1.0, tp_ratio: 1.5, sl_atr_multiplier: 1.2, 
    rsi_period: 14, rsi_overbought: 70, rsi_oversold: 30, min_confluence: 7, max_duration: 2,
    enable_vwap: true, enable_stoch: true, enable_institutional: true, enable_fibonacci: true,
    direction: 'BOTH',
    description: 'Cable 💷 Strong trends - Liquid pair' 
  }
}
