import { ref } from 'vue'
import axios from 'axios'
import { SYMBOL_PRESETS } from '../constants/presets.js'

export function useSlotManager(API_URL, showToastNotification = (msg, type) => console.log(`[Toast ${type}]: ${msg}`)) {
  const slots = ref([])

  // Helper to ensure we don't have duplicate IDs
  const getNextId = () => {
    if (slots.value.length === 0) return 1
    return Math.max(...slots.value.map(s => s.id)) + 1
  }

  // Add a new slot
  const addSlot = () => {
    const newId = getNextId()
    const defaultPreset = SYMBOL_PRESETS['EURUSD'] || {}
    
    slots.value.push({
      id: newId,
      dbId: null,  // Will be set when saved to DB
      symbol: 'EURUSD',
      enabled: true,
      expanded: true,
      isRunning: false,
      progress: 0,
      results: {},
      trades: [],
      sessionId: null,
      ...defaultPreset,
      direction: 'BOTH',
      risk_percent: 1.0,
      volume_mode: 'RISK',
      fixed_volume: 0.1,
      timeframe: 'M5',
      tp_ratio: 2.0,
      sl_atr_multiplier: 1.5,
      rsi_period: 14,
      rsi_overbought: 70,
      rsi_oversold: 30,
      min_confluence: 7,
      max_duration: 2,
      enable_vwap: true,
      enable_stoch: true,
      enable_institutional: true,
      enable_fibonacci: true,
      tsl_mode: 'TIERED',
      tsl_atr_multiplier: 1.5,
      tsl_activation_r: 0.0,
      partial_tp_on: true,
      // Institutional defaults
      confirmation_timeframe: 'M15',
      trading_session: 'ALL',
      session_end_action: 'HOLD',
      use_daily_bias: true,
      // Engine defaults
      engine_type: 'ADAPTIVE',
      zigzag_lookback: 12,
      enable_order_blocks: true,
      ob_lookback: 20,
      enable_liquidity_sweep: true,
      sweep_lookback: 10,
      enable_fvg: true,
      fvg_min_size_atr: 0.5,
      // Filters
      use_adx_filter: true,
      use_h1_trend_filter: false,
      vwap_use_trend_filter: true,
      stoch_k_period: 14,
      stoch_d_period: 3
    })
    
    showToastNotification('New slot added', 'info')
  }

  // Clone an existing slot
  const cloneSlot = (slotToClone) => {
    const newId = getNextId()
    const cloned = JSON.parse(JSON.stringify(slotToClone))
    cloned.id = newId
    cloned.dbId = null // Reset DB ID for new slot
    cloned.trades = [] // Reset trades/results
    cloned.results = {}
    cloned.progress = 0
    cloned.isRunning = false
    cloned.sessionId = null
    
    slots.value.push(cloned)
    showToastNotification(`Cloned slot ${slotToClone.symbol}`, 'success')
  }

  // Delete/Remove a slot
  const deleteSlot = (id) => {
    // If it has a DB ID, we might want to delete from DB too? 
    // For now, just remove from UI. If persistent sync is needed, add API call here.
    const slotIndex = slots.value.findIndex(s => s.id === id)
    if (slotIndex !== -1) {
      // Optional: Delete from DB if dbId exists
      const slot = slots.value[slotIndex]
      if (slot.dbId) {
          axios.delete(`${API_URL}/api/slots/${slot.dbId}`)
              .then(() => showToastNotification('Slot deleted from database', 'info'))
              .catch(err => console.warn('Failed to delete slot from DB', err))
      }
      
      slots.value.splice(slotIndex, 1)
      showToastNotification('Slot removed', 'info')
    }
  }

  // Apply preset when symbol changes
  const applySymbolPreset = (slot) => {
    const preset = SYMBOL_PRESETS[slot.symbol]
    if (preset) {
      // Apply all preset properties
      Object.assign(slot, {
          timeframe: preset.timeframe,
          tsl_mode: preset.tsl_mode,
          risk_percent: preset.risk_percent,
          tp_ratio: preset.tp_ratio,
          sl_atr_multiplier: preset.sl_atr_multiplier,
          rsi_period: preset.rsi_period,
          rsi_overbought: preset.rsi_overbought,
          rsi_oversold: preset.rsi_oversold,
          min_confluence: preset.min_confluence,
          max_duration: preset.max_duration,
          enable_vwap: preset.enable_vwap,
          enable_stoch: preset.enable_stoch,
          enable_institutional: preset.enable_institutional,
          enable_fibonacci: preset.enable_fibonacci,
          direction: preset.direction,
          // v3.0 props
          macd_fast: preset.macd_fast,
          macd_slow: preset.macd_slow,
          macd_signal: preset.macd_signal,
          session_mode: preset.session_mode
      })
      if (preset.zigzag_lookback) slot.zigzag_lookback = preset.zigzag_lookback
      
      showToastNotification(`Applied ${slot.symbol} preset`, 'success')
    }
  }

  // Save slot to database (debounced wrapper usually in UI, this is the core action)
  const saveSlot = async (slot) => {
    // Prepare payload (snake_case for backend)
    const payload = {
        symbol: slot.symbol,
        enabled: slot.enabled,
        direction_filter: slot.direction,
        timeframe: slot.timeframe,
        risk_percent: slot.risk_percent,
        tp_ratio: slot.tp_ratio,
        sl_atr_multiplier: slot.sl_atr_multiplier,
        tsl_mode: slot.tsl_mode,
        rsi_period: slot.rsi_period,
        rsi_overbought: slot.rsi_overbought || slot.config?.rsi_sell_threshold || 70,
        rsi_oversold: slot.rsi_oversold || slot.config?.rsi_buy_threshold || 30,
        min_confluence_score: slot.min_confluence,
        max_trade_duration_hours: slot.max_duration,
        enable_vwap_strategy: slot.enable_vwap,
        enable_stoch_strategy: slot.enable_stoch,
        enable_institutional_strategy: slot.enable_institutional,
        enable_fibonacci_strategy: slot.enable_fibonacci,
        partial_tp_on: slot.partial_tp_on,
        
        // Institutional
        confirmation_timeframe: slot.confirmation_timeframe,
        trading_session: slot.trading_session,
        session_end_action: slot.session_end_action,
        use_daily_bias: slot.use_daily_bias,
        
        // Engine
        engine_type: slot.engine_type,
        zigzag_lookback: slot.zigzag_lookback,
        enable_order_blocks: slot.enable_order_blocks,
        ob_lookback: slot.ob_lookback,
        enable_liquidity_sweep: slot.enable_liquidity_sweep,
        sweep_lookback: slot.sweep_lookback,
        enable_fvg: slot.enable_fvg,
        fvg_min_size_atr: slot.fvg_min_size_atr,

        // Filters
        use_adx_filter: slot.use_adx_filter,
        use_h1_trend_filter: slot.use_h1_trend_filter,
        vwap_use_trend_filter: slot.vwap_use_trend_filter,
        
        // Misc
        macd_fast: slot.config?.macd_fast || 12,
        macd_slow: slot.config?.macd_slow || 26,
        macd_signal: slot.config?.macd_signal || 9
    }

    try {
      if (slot.dbId) {
        // Update existing
        await axios.put(`${API_URL}/api/slots/${slot.dbId}`, payload)
        // console.log(`💾 Saved slot ${slot.dbId}`)
      } else {
        // Create new
        const response = await axios.post(`${API_URL}/api/slots/`, payload)
        slot.dbId = response.data.id
        console.log(`💾 Created new slot ID ${slot.dbId}`)
        showToastNotification('Slot saved to database', 'success')
      }
    } catch (error) {
      if (error.response && error.response.status === 404 && slot.dbId) {
        console.warn(`⚠️ Slot ${slot.dbId} not found in DB (404). Re-creating...`)
        try {
           const response = await axios.post(`${API_URL}/api/slots/`, payload)
           slot.dbId = response.data.id
           showToastNotification('Sync: Slot re-created on server', 'info')
        } catch (createError) {
           console.error('Failed to re-create slot:', createError)
        }
      } else {
        console.error('Failed to save slot:', error)
        showToastNotification('❌ Failed to save: ' + (error.response?.data?.detail || error.message), 'error')
      }
    }
  }

  // Load slots from database
  const loadSlots = async () => {
    try {
      const response = await axios.get(`${API_URL}/api/slots/`)
      const dbSlots = response.data
      
      if (dbSlots.length > 0) {
        // Map DB slots to UI model
        slots.value = dbSlots.map((dbSlot, index) => ({
          id: index + 1, // Start IDs from 1
          dbId: dbSlot.id,
          symbol: dbSlot.symbol,
          enabled: dbSlot.enabled,
          expanded: index === 0,
          isRunning: false,
          progress: 0,
          results: {},
          trades: [],
          sessionId: null,
          direction: dbSlot.direction_filter,
          timeframe: dbSlot.timeframe,
          risk_percent: dbSlot.risk_percent,
          tp_ratio: dbSlot.tp_ratio,
          sl_atr_multiplier: dbSlot.sl_atr_multiplier,
          tsl_mode: dbSlot.tsl_mode,
          rsi_period: dbSlot.rsi_period,
          rsi_overbought: dbSlot.rsi_overbought,
          rsi_oversold: dbSlot.rsi_oversold,
          min_confluence: dbSlot.min_confluence_score,
          max_duration: dbSlot.max_trade_duration_hours,
          enable_vwap: dbSlot.enable_vwap_strategy,
          enable_stoch: dbSlot.enable_stoch_strategy,
          enable_institutional: dbSlot.enable_institutional_strategy,
          enable_fibonacci: dbSlot.enable_fibonacci_strategy,
          partial_tp_on: dbSlot.partial_tp_on,
          
          confirmation_timeframe: dbSlot.confirmation_timeframe,
          trading_session: dbSlot.trading_session,
          session_mode: dbSlot.trading_session, 
          session_end_action: dbSlot.session_end_action,
          use_daily_bias: dbSlot.use_daily_bias,
          
          engine_type: dbSlot.engine_type || 'XAU_PRO',
          zigzag_lookback: dbSlot.zigzag_lookback,
          
          enable_order_blocks: dbSlot.enable_order_blocks,
          ob_lookback: dbSlot.ob_lookback,
          enable_liquidity_sweep: dbSlot.enable_liquidity_sweep,
          sweep_lookback: dbSlot.sweep_lookback,
          enable_fvg: dbSlot.enable_fvg,
          fvg_min_size_atr: dbSlot.fvg_min_size_atr,
          
          use_adx_filter: dbSlot.use_adx_filter,
          use_h1_trend_filter: dbSlot.use_h1_trend_filter,
          vwap_use_trend_filter: dbSlot.vwap_use_trend_filter,
          
          config: {
              macd_fast: dbSlot.macd_fast,
              macd_slow: dbSlot.macd_slow,
              macd_signal: dbSlot.macd_signal,
              rsi_period: dbSlot.rsi_period,
              rsi_buy_threshold: dbSlot.rsi_oversold,
              rsi_sell_threshold: dbSlot.rsi_overbought
          } || {}
        }))
        console.log(`📦 Loaded ${dbSlots.length} slots from database`)
      }
    } catch (error) {
      console.error('Failed to load slots from database:', error)
      showToastNotification('Failed to load slots', 'error')
    }
  }

  return {
    slots,
    addSlot,
    cloneSlot,
    deleteSlot,
    applySymbolPreset,
    saveSlot,
    loadSlots
  }
}
