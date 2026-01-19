import { ref } from 'vue'
import socket from '../services/socket'

export function useSocketTrading(
  slots,
  sharedConfig,
  trades,  // legacy global trades list
  isRunning,
  backtestStatus,
  killSwitchActive,
  riskStatus,
  tradingMode,
  showToastNotification,
  fetchHistory
) {

    // Ensure socket is connected helper
    const ensureSocketConnected = () => {
        return new Promise((resolve, reject) => {
            if (socket.connected) {
                resolve()
                return
            }

            console.log('🔌 Connecting socket...')
            socket.connect()

            const timeout = setTimeout(() => {
                reject(new Error('Socket connection timeout'))
            }, 5000)

            socket.once('connect', () => {
                clearTimeout(timeout)
                console.log('✅ Socket connected')
                resolve()
            })
        })
    }

    // Socket Event Listeners
    const setupSocketListeners = () => {
        // Remove existing listeners to avoid duplicates if re-mounted (clean update)
        socket.off('backtest_progress')
        socket.off('backtest_trade')
        socket.off('backtest_complete')
        socket.off('backtest_error')
        socket.off('live_trade_opened')
        socket.off('live_trade_closed')
        socket.off('trailing_stop_moved')
        socket.off('market_update')
        socket.off('risk_update')

        socket.on('backtest_progress', (data) => {
            // Find slot by session_id
            const slot = slots.value.find(s => s.sessionId === data.session_id)
            if (slot) {
                slot.progress = Math.round(data.progress)
                if (data.stats) {
                    slot.results = {
                        ...slot.results,
                        net_profit: data.stats.balance - sharedConfig.value.initial_balance,
                        total_trades: data.stats.trades,
                    }
                }
            }
        })

        socket.on('backtest_trade', (data) => {
            const trade = data.trade
            const slot = slots.value.find(s => s.sessionId === data.session_id)
            
            if (trade.type === 'CLOSE') {
                const tradeObj = {
                    id: Date.now() + Math.random(),
                    symbol: slot?.symbol || '-',
                    entry_time: trade.entry_time,
                    exit_time: trade.exit_time,
                    trade_type: trade.trade_type,
                    entry_price: trade.entry_price,
                    exit_price: trade.price,
                    profit: trade.pnl,
                    balance_after: trade.balance
                }
                
                // Add to slot's trades
                if (slot) {
                    slot.trades.unshift(tradeObj)
                    slot.results.net_profit = trade.balance - sharedConfig.value.initial_balance
                }
                
                // Add to global trades list
                trades.value.unshift(tradeObj)
            }
        })

        socket.on('backtest_complete', (data) => {
            const slot = slots.value.find(s => s.sessionId === data.session_id)
            if (slot) {
                slot.isRunning = false
                slot.progress = 100
                slot.results = data.results

                // Show completion notification
                const profit = data.results.net_profit || 0
                const profitSign = profit >= 0 ? '+' : ''
                if (showToastNotification) {
                    showToastNotification(
                        `${slot.symbol} backtest complete! P/L: ${profitSign}$${profit.toFixed(2)}`,
                        profit >= 0 ? 'success' : 'warning',
                        4000
                    )
                }
            }

            // Check if all slots are done
            const anyRunning = slots.value.some(s => s.isRunning)
            if (!anyRunning) {
                isRunning.value = false
                backtestStatus.value = ''
                if (fetchHistory) fetchHistory()
                if (showToastNotification) showToastNotification('All backtests completed!', 'success', 4000)
            }
        })

        socket.on('backtest_error', (data) => {
            console.error('❌ Backtest error:', data)
            const slot = slots.value.find(s => s.sessionId === data.session_id)
            if (slot) {
                slot.isRunning = false
                slot.progress = 0
                if (showToastNotification) showToastNotification(`${slot.symbol}: ${data.error}`, 'error', 6000)
            }

            const anyRunning = slots.value.some(s => s.isRunning)
            if (!anyRunning) {
                isRunning.value = false
                backtestStatus.value = ''
            }
        })
        
        // 🔴 LIVE TRADING
        socket.on('live_trade_opened', (trade) => {
            const slot = slots.value.find(s => s.sessionId === trade.session_id)

            const tradeObj = {
                id: trade.ticket,
                symbol: trade.symbol,
                entry_time: trade.opened_at,
                exit_time: null,
                trade_type: trade.type,
                entry_price: trade.entry_price,
                exit_price: null,
                stop_loss: trade.stop_loss,
                take_profit: trade.take_profit,
                volume: trade.volume,
                profit: 0,
                status: 'OPEN'
            }

            if (slot) {
                if (!slot.trades) slot.trades = []
                slot.trades.unshift(tradeObj)
            }

            trades.value.unshift(tradeObj)

            if (showToastNotification) {
                showToastNotification(
                    `🔴 ${trade.type} ${trade.symbol} @ ${trade.entry_price}`,
                    'info',
                    3000
                )
            }
        })
        
        socket.on('live_trade_closed', (data) => {
            const slot = slots.value.find(s => s.sessionId === data.session_id)
            if (slot) {
                const trade = slot.trades.find(t => t.id === data.ticket)
                if (trade) {
                    trade.status = 'CLOSED'
                    trade.exit_time = data.closed_at
                    trade.profit = data.pnl

                    const profitSign = data.pnl >= 0 ? '+' : ''
                    if (showToastNotification) {
                        showToastNotification(
                            `${trade.symbol} closed: ${profitSign}$${data.pnl.toFixed(2)}`,
                            data.pnl >= 0 ? 'success' : 'error',
                            4000
                        )
                    }
                }
            }

            const legacyTrade = trades.value.find(t => t.id === data.ticket)
            if (legacyTrade) {
                legacyTrade.status = 'CLOSED'
                legacyTrade.exit_time = data.closed_at
                legacyTrade.profit = data.pnl
            }
        })
        
        socket.on('trailing_stop_moved', (data) => {
            const slot = slots.value.find(s => s.sessionId === data.session_id)
            if (slot) {
                const trade = slot.trades.find(t => t.id === data.ticket)
                if (trade) trade.stop_loss = data.new_sl
            }
        })
        
        socket.on('market_update', (data) => {
            if (tradingMode.value !== 'live') return
            
            if (data.positions) {
                data.positions.forEach(pos => {
                    slots.value.forEach(slot => {
                        const trade = slot.trades?.find(t => t.id === pos.ticket)
                        if (trade) {
                            trade.profit = pos.profit
                            trade.current_price = pos.price_current
                        }
                    })
                    
                    const legacyTrade = trades.value.find(t => t.id === pos.ticket)
                    if (legacyTrade) legacyTrade.profit = pos.profit
                })
            }
        })

        socket.on('risk_update', (data) => {
            killSwitchActive.value = data.kill_switch
            riskStatus.value = data
            
            if (data.kill_switch) {
                if (isRunning.value) {
                    isRunning.value = false
                    if (showToastNotification) showToastNotification(`⚠️ System halted: ${data.kill_switch_reason}`, 'risk', 0)
                }
            }
        })
    }

    // Unmount cleanup
    const cleanupSocketListeners = () => {
        socket.off('backtest_progress')
        socket.off('backtest_trade')
        socket.off('backtest_complete')
        socket.off('backtest_error')
        socket.off('live_trade_opened')
        socket.off('live_trade_closed')
        socket.off('trailing_stop_moved')
        socket.off('market_update')
        socket.off('risk_update')
    }

    return {
        ensureSocketConnected,
        setupSocketListeners,
        cleanupSocketListeners
    }
}
