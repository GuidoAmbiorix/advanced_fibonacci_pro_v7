import { computed } from 'vue'

export function usePortfolioMetrics(slots) {

  // Computed: Total active risk (sum of risk % for slots with open positions)
  const totalActiveRisk = computed(() => {
    return slots.value
      .filter(s => s.enabled && s.trades.some(t => t.status === 'OPEN' || !t.exit_time))
      .reduce((sum, s) => sum + (s.risk_percent || 1.0), 0)
  })

  // Computed: Total potential risk (sum of risk % for all enabled slots)
  const totalPotentialRisk = computed(() => {
    return slots.value
      .filter(s => s.enabled)
      .reduce((sum, s) => sum + (s.risk_percent || 1.0), 0)
  })

  // Computed: Open position count
  const openPositionCount = computed(() => {
    return slots.value.reduce((count, s) => {
      // Check both t.status and exit_time for robustness
      return count + s.trades.filter(t => t.status === 'OPEN' || !t.exit_time).length
    }, 0)
  })

  // PORTFOLIO COMBINED METRICS (computed from all enabled slots)
  const portfolioMetrics = computed(() => {
    const enabledSlots = slots.value.filter(s => s.enabled)
    
    // Sum up all metrics
    let totalNetProfit = 0
    let totalTrades = 0
    let totalWins = 0
    let totalGrossProfit = 0
    let totalGrossLoss = 0
    let maxDrawdown = 0
    
    enabledSlots.forEach(slot => {
      // Prefer results if available (finalized stats), otherwise calc from trades
      const hasResults = slot.results && slot.results.total_trades !== undefined
      
      if (hasResults) {
        if (slot.results.total_trades) {
          totalTrades += slot.results.total_trades
          totalWins += Math.round(slot.results.total_trades * (slot.results.win_rate || 0) / 100)
        }
        if (slot.results.net_profit !== undefined) totalNetProfit += slot.results.net_profit
        if (slot.results.gross_profit) totalGrossProfit += slot.results.gross_profit
        if (slot.results.gross_loss) totalGrossLoss += Math.abs(slot.results.gross_loss)
        if (slot.results.max_drawdown && slot.results.max_drawdown > maxDrawdown) {
          maxDrawdown = slot.results.max_drawdown
        }
      } else if (slot.trades && slot.trades.length > 0) {
        // Fallback: Real-time calculation from trades list
        const closedTrades = slot.trades.filter(t => t.exit_time || t.status === 'CLOSED')
        
        totalTrades += closedTrades.length
        totalWins += closedTrades.filter(t => (t.profit || 0) > 0).length
        totalNetProfit += closedTrades.reduce((sum, t) => sum + (t.profit || 0), 0)
        
        let runningBalance = 0
        let peakBalance = 0
        let currentDrawdown = 0
        let slotMaxDrawdown = 0
        
        closedTrades.forEach(t => {
          const profit = t.profit || 0
          if (profit > 0) totalGrossProfit += profit
          else totalGrossLoss += Math.abs(profit)
          
          // Calculate Max DD from trade sequence
          runningBalance += profit
          if (runningBalance > peakBalance) peakBalance = runningBalance
          const dd = peakBalance - runningBalance
          if (dd > slotMaxDrawdown) slotMaxDrawdown = dd
        })
        
        if (slotMaxDrawdown > 0) {
           if (slotMaxDrawdown > maxDrawdown) maxDrawdown = slotMaxDrawdown 
        }
      }
    })
    
    // Calculate combined metrics
    const winRate = totalTrades > 0 ? (totalWins / totalTrades * 100) : 0
    const profitFactor = totalGrossLoss > 0 ? (totalGrossProfit / totalGrossLoss) : (totalGrossProfit > 0 ? 999 : 0)
    
    return {
      netProfit: totalNetProfit,
      winRate: winRate,
      maxDrawdown: maxDrawdown,
      totalTrades: totalTrades,
      profitFactor: profitFactor
    }
  })

  return {
    portfolioMetrics,
    totalActiveRisk,
    totalPotentialRisk,
    openPositionCount
  }
}
