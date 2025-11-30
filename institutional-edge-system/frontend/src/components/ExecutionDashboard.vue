<template>
  <div class="min-h-screen bg-background text-text-secondary font-sans flex flex-col selection:bg-accent/30">
    <!-- Header -->
    <header class="bg-surface/90 backdrop-blur-md border-b border-slate-200 p-4 flex justify-between items-center sticky top-0 z-50 shadow-sm">
      <div class="flex items-center space-x-6">
        <div class="flex flex-col">
          <div class="text-2xl font-black tracking-tighter text-primary">
            INSTITUTIONAL <span class="text-accent">EDGE</span>
          </div>
          <div class="text-[10px] font-mono text-slate-500 tracking-[0.2em] uppercase">
            Professional Execution Terminal
          </div>
        </div>
        
        <!-- Account Info -->
        <div v-if="accountInfo" class="hidden md:flex items-center space-x-4 bg-slate-50 px-4 py-2 rounded-lg border border-slate-200">
           <div class="flex flex-col">
             <span class="text-[10px] text-slate-500 font-bold uppercase tracking-wider">Balance</span>
             <span class="text-sm font-mono font-bold text-primary">{{ formatCurrency(accountInfo.balance) }}</span>
           </div>
           <div class="w-px h-6 bg-slate-200"></div>
           <div class="flex flex-col">
             <span class="text-[10px] text-slate-500 font-bold uppercase tracking-wider">Equity</span>
             <span class="text-sm font-mono font-bold" :class="accountInfo.equity >= accountInfo.balance ? 'text-success' : 'text-danger'">{{ formatCurrency(accountInfo.equity) }}</span>
           </div>
           <div class="w-px h-6 bg-slate-200"></div>
           <div class="flex items-center space-x-2">
             <div class="w-2 h-2 rounded-full" :class="isSocketConnected ? 'bg-success' : 'bg-danger animate-pulse'"></div>
             <span class="text-[10px] font-bold uppercase tracking-wider" :class="isSocketConnected ? 'text-success' : 'text-danger'">{{ isSocketConnected ? 'LIVE' : 'OFFLINE' }}</span>
           </div>
        </div>
      </div>

      <div class="flex items-center space-x-6">
        <!-- Symbol & Timeframe Selector -->
        <div class="flex items-center bg-slate-50 rounded-lg p-1.5 border border-slate-200 space-x-3 shadow-inner">
          <div class="flex items-center px-2">
            <span class="text-[10px] font-bold px-2 text-slate-500 tracking-wider">SYMBOL</span>
            <select v-model="selectedSymbol" @change="onSymbolChange" class="bg-white text-primary text-xs font-bold px-3 py-1.5 rounded border border-slate-200 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all cursor-pointer hover:bg-slate-50">
              <option v-for="sym in availableSymbols" :key="sym.symbol" :value="sym.symbol">
                {{ sym.symbol }}
              </option>
            </select>
            <button @click="openAddMarketModal" class="ml-2 text-accent hover:text-accent-hover transition-colors" title="Add New Market">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-11a1 1 0 10-2 0v2H7a1 1 0 100 2h2v2a1 1 0 102 0v-2h2a1 1 0 100-2h-2V7z" clip-rule="evenodd" />
              </svg>
            </button>
          </div>
          <div class="w-px h-6 bg-slate-200"></div>
          <div class="flex items-center px-2">
            <span class="text-[10px] font-bold px-2 text-slate-500 tracking-wider">TIMEFRAME</span>
            <select v-model="selectedTimeframe" @change="onTimeframeChange" class="bg-white text-primary text-xs font-bold px-3 py-1.5 rounded border border-slate-200 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all cursor-pointer hover:bg-slate-50">
              <option value="M1">M1</option>
              <option value="M5">M5</option>
              <option value="M15">M15</option>
              <option value="H1">H1</option>
              <option value="H4">H4</option>
              <option value="D1">D1</option>
            </select>
          </div>
        </div>

        <!-- Bot Control -->
        <div class="flex items-center space-x-3">
          <router-link to="/performance" class="px-4 py-2 rounded-lg font-bold text-xs bg-white hover:bg-slate-50 text-purple-600 border border-purple-200 transition-all shadow-sm hover:shadow-md">
            STATS
          </router-link>
          
          <button 
            @click="toggleBot" 
            class="group relative px-6 py-2 rounded-lg font-bold text-sm transition-all duration-300 shadow-sm hover:shadow-md overflow-hidden"
            :class="isBotRunning ? 'bg-danger/10 text-danger border border-danger/20 hover:bg-danger/20' : 'bg-success/10 text-success border border-success/20 hover:bg-success/20'"
          >
            <div class="flex items-center space-x-3">
              <span class="relative flex h-2.5 w-2.5">
                <span v-if="isBotRunning" class="animate-ping absolute inline-flex h-full w-full rounded-full bg-danger opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2.5 w-2.5" :class="isBotRunning ? 'bg-danger' : 'bg-success'"></span>
              </span>
              <span class="tracking-wider">{{ isBotRunning ? 'STOP ALGO' : 'START ALGO' }}</span>
            </div>
          </button>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main class="flex-1 p-6 grid grid-cols-12 gap-6 overflow-hidden">
      
      <!-- Left Column: Signals & Execution (4 cols) -->
      <div class="col-span-4 flex flex-col space-y-6 h-full overflow-hidden">
        <!-- Trading Plan Config -->
        <div class="bg-white border border-slate-200 rounded-xl p-5 shadow-card">
          <div class="flex justify-between items-center mb-6">
             <div class="flex items-center space-x-2">
               <div class="w-1 h-4 bg-accent rounded-full"></div>
               <h3 class="text-primary text-sm font-bold tracking-wide">TRADING PLAN</h3>
             </div>
             <button @click="saveConfig" class="text-[10px] bg-accent hover:bg-accent-hover px-3 py-1.5 rounded text-white font-bold tracking-wider transition-all shadow-sm">SAVE CONFIG</button>
          </div>
          
          <div class="space-y-5">
            <!-- Risk & BE -->
            <div class="grid grid-cols-2 gap-4">
              <div class="group">
                <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1.5 block group-focus-within:text-accent transition-colors">Risk per Trade (%)</label>
                <div class="relative">
                  <input type="number" v-model.number="tradingPlan.risk_percent" step="0.1" class="w-full bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm font-mono text-primary focus:border-accent focus:ring-1 focus:ring-accent outline-none transition-all">
                  <span class="absolute right-3 top-2 text-slate-400 text-xs">%</span>
                </div>
              </div>
              <div class="group">
                <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1.5 block group-focus-within:text-accent transition-colors">BE Trigger (R)</label>
                <div class="relative">
                  <input type="number" v-model.number="tradingPlan.be_trigger" step="0.1" class="w-full bg-slate-50 border border-slate-200 rounded-lg px-3 py-2 text-sm font-mono text-primary focus:border-accent focus:ring-1 focus:ring-accent outline-none transition-all">
                  <span class="absolute right-3 top-2 text-slate-400 text-xs">R</span>
                </div>
              </div>
            </div>

            <!-- Trailing SL -->
            <div class="bg-slate-50 p-3 rounded-lg border border-slate-200 hover:border-slate-300 transition-colors">
              <div class="flex items-center justify-between mb-3">
                <label class="text-xs text-primary font-bold">Trailing Stop Loss</label>
                <input type="checkbox" v-model="tradingPlan.trailing_sl" class="w-4 h-4 text-accent bg-white border-slate-300 rounded focus:ring-accent focus:ring-2">
              </div>
              <div v-if="tradingPlan.trailing_sl" class="grid grid-cols-1 gap-2 animate-fadeIn mt-2">
                 <div class="grid grid-cols-2 gap-2">
                    <div>
                      <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1 block">Mode</label>
                      <select v-model="tradingPlan.tsl_mode" class="w-full bg-white border border-slate-200 rounded px-2 py-1.5 text-xs font-mono focus:border-accent outline-none text-primary">
                        <option value="FIXED">Fixed</option>
                        <option value="ATR">ATR Dynamic</option>
                      </select>
                    </div>
                    <div>
                      <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1 block">Activation (R)</label>
                      <input type="number" v-model.number="tradingPlan.tsl_activation_r" step="0.1" class="w-full bg-white border border-slate-200 rounded px-2 py-1.5 text-xs font-mono focus:border-accent outline-none text-primary">
                    </div>
                 </div>

                 <div v-if="tradingPlan.tsl_mode === 'FIXED'" class="grid grid-cols-2 gap-2">
                    <div>
                      <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1 block">Step (R)</label>
                      <input type="number" v-model.number="tradingPlan.trailing_step" step="0.1" class="w-full bg-white border border-slate-200 rounded px-2 py-1.5 text-xs font-mono focus:border-accent outline-none text-primary">
                    </div>
                     <div>
                      <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1 block">Distance (R)</label>
                      <input type="number" v-model.number="tradingPlan.trailing_distance" step="0.1" class="w-full bg-white border border-slate-200 rounded px-2 py-1.5 text-xs font-mono focus:border-accent outline-none text-primary">
                    </div>
                 </div>

                 <div v-if="tradingPlan.tsl_mode === 'ATR'" class="grid grid-cols-2 gap-2 bg-white p-2 rounded border border-slate-200">
                    <div>
                      <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1 block">ATR Period</label>
                      <input type="number" v-model.number="tradingPlan.tsl_atr_period" class="w-full bg-white border border-slate-200 rounded px-2 py-1.5 text-xs font-mono focus:border-accent outline-none text-primary">
                    </div>
                     <div>
                      <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1 block">Multiplier</label>
                      <input type="number" v-model.number="tradingPlan.tsl_atr_multiplier" step="0.1" class="w-full bg-white border border-slate-200 rounded px-2 py-1.5 text-xs font-mono focus:border-accent outline-none text-primary">
                    </div>
                 </div>
              </div>
            </div>

            <!-- Partial TP -->
            <div class="bg-slate-50 p-3 rounded-lg border border-slate-200 hover:border-slate-300 transition-colors">
              <div class="flex items-center justify-between mb-3">
                <label class="text-xs text-primary font-bold">Partial Take Profit</label>
                <input type="checkbox" v-model="tradingPlan.partial_tp_on" class="w-4 h-4 text-accent bg-white border-slate-300 rounded focus:ring-accent focus:ring-2">
              </div>
              <div v-if="tradingPlan.partial_tp_on" class="grid grid-cols-1 gap-2 animate-fadeIn">
                 <div>
                  <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1 block">Amount (0.1 - 1.0)</label>
                  <input type="number" v-model.number="tradingPlan.partial_tp_amount" step="0.1" max="1.0" class="w-full bg-white border border-slate-200 rounded px-2 py-1.5 text-xs font-mono focus:border-accent outline-none text-primary">
                </div>
              </div>
            </div>

            <!-- Filters -->
             <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1.5 block">Max Spread</label>
                <input type="number" v-model.number="tradingPlan.max_spread" step="0.1" class="w-full bg-slate-50 border border-slate-200 rounded px-3 py-2 text-xs font-mono focus:border-accent outline-none text-primary">
              </div>
              <div>
                <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1.5 block">Daily Loss %</label>
                <input type="number" v-model.number="tradingPlan.daily_loss_limit_percent" step="0.5" class="w-full bg-slate-50 border border-slate-200 rounded px-3 py-2 text-xs font-mono focus:border-accent outline-none text-primary">
              </div>
            </div>
             <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1.5 block">Start Time</label>
                <input type="time" v-model="tradingPlan.trading_hours_start" class="w-full bg-slate-50 border border-slate-200 rounded px-3 py-2 text-xs font-mono focus:border-accent outline-none text-primary">
              </div>
              <div>
                <label class="text-[10px] text-slate-500 font-bold uppercase tracking-wider mb-1.5 block">End Time</label>
                <input type="time" v-model="tradingPlan.trading_hours_end" class="w-full bg-slate-50 border border-slate-200 rounded px-3 py-2 text-xs font-mono focus:border-accent outline-none text-primary">
              </div>
            </div>

          </div>
        </div>

        <!-- Signal Feed / Activity Log Toggle -->
        <div class="bg-white border border-slate-200 rounded-xl p-0 shadow-card flex-1 overflow-hidden flex flex-col">
          <div class="flex border-b border-slate-200">
            <button 
              @click="activeTab = 'signals'" 
              class="flex-1 py-3 text-xs font-bold uppercase tracking-widest transition-all relative overflow-hidden group"
              :class="activeTab === 'signals' ? 'text-accent bg-slate-50' : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'"
            >
              <span class="relative z-10">Signals</span>
              <div v-if="activeTab === 'signals'" class="absolute bottom-0 left-0 w-full h-0.5 bg-accent"></div>
            </button>
            <button 
              @click="activeTab = 'logs'" 
              class="flex-1 py-3 text-xs font-bold uppercase tracking-widest transition-all relative overflow-hidden group"
              :class="activeTab === 'logs' ? 'text-success bg-slate-50' : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'"
            >
              <span class="relative z-10">Activity Log</span>
              <div v-if="activeTab === 'logs'" class="absolute bottom-0 left-0 w-full h-0.5 bg-success"></div>
            </button>
            <button 
              @click="activeTab = 'fundamentals'" 
              class="flex-1 py-3 text-xs font-bold uppercase tracking-widest transition-all relative overflow-hidden group"
              :class="activeTab === 'fundamentals' ? 'text-purple-600 bg-slate-50' : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'"
            >
              <span class="relative z-10">Fundamentals</span>
              <div v-if="activeTab === 'fundamentals'" class="absolute bottom-0 left-0 w-full h-0.5 bg-purple-600"></div>
            </button>
          </div>
          
          <!-- Signals Tab -->
          <div v-if="activeTab === 'signals'" class="overflow-y-auto flex-1 p-4 space-y-3 custom-scrollbar">
            <div class="flex justify-between items-center mb-2">
               <span class="text-[10px] text-slate-500 font-bold uppercase">Latest Signals</span>
               <div class="flex space-x-2">
                 <button @click="clearSignals" class="text-[10px] text-danger hover:text-red-600 font-bold">CLEAR</button>
                 <button @click="fetchSignals" class="text-[10px] text-accent hover:text-accent-hover font-bold">REFRESH</button>
               </div>
            </div>

            <div v-for="signal in signals" :key="signal.id" class="bg-slate-50 border border-slate-200 rounded-lg p-4 hover:border-accent/50 transition-all group relative overflow-hidden">
              <div class="absolute top-0 left-0 w-1 h-full" :class="signal.signal_type === 'BUY' ? 'bg-success' : 'bg-danger'"></div>
              
              <div class="flex justify-between items-start mb-3 pl-2">
                <div>
                  <div class="flex items-center space-x-2">
                    <span class="font-black text-lg tracking-tight" :class="signal.signal_type === 'BUY' ? 'text-success' : 'text-danger'">
                      {{ signal.signal_type }}
                    </span>
                    <span class="text-slate-500 text-xs font-bold bg-white border border-slate-200 px-1.5 py-0.5 rounded">{{ signal.symbol }}</span>
                  </div>
                </div>
                <div class="text-[10px] text-slate-400 font-mono">{{ formatTimeAgo(signal.created_at) }}</div>
              </div>
              
              <div class="grid grid-cols-2 gap-y-1 gap-x-4 text-xs mb-4 pl-2">
                <div class="flex justify-between">
                  <span class="text-slate-500">Entry</span>
                  <span class="font-mono text-primary">{{ signal.price }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-500">SL</span>
                  <span class="font-mono text-danger">{{ signal.stop_loss }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-500">TP1</span>
                  <span class="font-mono text-success">{{ signal.take_profit }}</span>
                </div>
                <div class="flex justify-between">
                  <span class="text-slate-500">Score</span>
                  <span class="font-bold text-warning">{{ signal.confluence_score }}/10</span>
                </div>
              </div>

              <button 
                v-if="!signal.was_executed"
                @click="executeSignal(signal)"
                class="w-full py-2 rounded-lg font-bold text-xs bg-accent hover:bg-accent-hover text-white transition-all shadow-sm transform active:scale-95"
              >
                EXECUTE TRADE
              </button>
              <div v-else class="text-center text-[10px] text-slate-400 font-mono py-2 bg-slate-100 rounded border border-slate-200">
                EXECUTED
              </div>
            </div>
            
            <div v-if="signals.length === 0" class="text-center text-slate-400 py-12 flex flex-col items-center">
              <div class="text-4xl mb-2 opacity-20">📡</div>
              <span class="text-xs">Scanning market...</span>
            </div>
          </div>

          <!-- Activity Log Tab -->
          <div v-else-if="activeTab === 'logs'" class="flex-1 overflow-hidden bg-slate-50">
            <ActivityLog />
          </div>

          <!-- Fundamentals Tab -->
          <div v-else-if="activeTab === 'fundamentals'" class="flex-1 overflow-hidden bg-slate-50 p-2">
            <FundamentalWidget :symbol="selectedSymbol" />
          </div>
        </div>
      </div>

      <!-- Center & Right: Chart & Trades (8 cols) -->
      <div class="col-span-8 flex flex-col space-y-6 h-full overflow-hidden">
        <!-- Chart Area -->
        <div class="bg-white border border-slate-200 rounded-xl p-1 shadow-card h-[500px] relative flex flex-col">
           <div class="absolute top-4 left-4 z-10 flex space-x-2">
             <div class="bg-white/90 backdrop-blur px-3 py-1 rounded text-xs font-bold text-primary border border-slate-200 shadow-sm">
               {{ selectedSymbol }} <span class="text-slate-400">|</span> {{ selectedTimeframe }}
             </div>
           </div>
           <div class="w-full h-full p-2 bg-slate-50 rounded-lg">
             <TradingChart 
                :data="chartData" 
                :trades="openTrades" 
                :symbol="selectedSymbol"
                :is-dark="false"
             />
          </div>
        </div>

        <!-- Open Trades -->
        <div class="bg-white border border-slate-200 rounded-xl p-5 shadow-card flex-1 flex flex-col overflow-hidden">
          <div class="flex justify-between items-center mb-4">
             <div class="flex items-center space-x-2">
               <div class="w-1 h-4 bg-success rounded-full"></div>
               <h3 class="text-primary text-sm font-bold tracking-wide">OPEN POSITIONS</h3>
             </div>
             <div class="text-xs font-mono text-slate-500">
               Total PnL: <span :class="totalPnL >= 0 ? 'text-success' : 'text-danger'" class="font-bold">{{ formatCurrency(totalPnL || 0) }}</span>
             </div>
          </div>
          
          <div class="overflow-x-auto flex-1 custom-scrollbar">
            <table class="w-full text-sm text-left border-collapse">
              <thead class="text-[10px] text-slate-500 uppercase bg-slate-50 sticky top-0 z-10">
                <tr>
                  <th class="px-4 py-3 font-bold tracking-wider rounded-tl-lg">Ticket</th>
                  <th class="px-4 py-3 font-bold tracking-wider">Symbol</th>
                  <th class="px-4 py-3 font-bold tracking-wider">Type</th>
                  <th class="px-4 py-3 font-bold tracking-wider">Vol</th>
                  <th class="px-4 py-3 font-bold tracking-wider">Entry</th>
                  <th class="px-4 py-3 font-bold tracking-wider">Current</th>
                  <th class="px-4 py-3 font-bold tracking-wider">PnL</th>
                  <th class="px-4 py-3 font-bold tracking-wider rounded-tr-lg text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-200">
                <tr v-for="trade in openTrades" :key="trade.ticket" class="hover:bg-slate-50 transition-colors group">
                  <td class="px-4 py-3 font-mono text-slate-500 text-xs">{{ trade.ticket }}</td>
                  <td class="px-4 py-3 font-bold text-primary">{{ trade.symbol }}</td>
                  <td class="px-4 py-3 text-xs font-bold" :class="trade.type === 'BUY' ? 'text-success' : 'text-danger'">{{ trade.type }}</td>
                  <td class="px-4 py-3 text-primary font-mono text-xs">{{ trade.volume }}</td>
                  <td class="px-4 py-3 font-mono text-slate-500 text-xs">{{ trade.entry }}</td>
                  <td class="px-4 py-3 font-mono text-slate-500 text-xs">{{ trade.current }}</td>
                  <td class="px-4 py-3 font-mono font-bold text-xs" :class="trade.pnl >= 0 ? 'text-success' : 'text-danger'">
                    {{ formatCurrency(trade.pnl) }}
                  </td>
                  <td class="px-4 py-3 text-right">
                    <button @click="moveToBE(trade.ticket)" class="text-[10px] bg-slate-100 hover:bg-slate-200 text-primary px-2 py-1 rounded mr-2 transition-colors border border-slate-200">BE</button>
                    <button @click="trailSL(trade.ticket)" class="text-[10px] bg-accent/10 hover:bg-accent/20 text-accent border border-accent/30 px-2 py-1 rounded mr-2 transition-colors">TRAIL</button>
                    <button @click="closeTrade(trade.ticket)" class="text-[10px] bg-danger/10 hover:bg-danger/20 text-danger border border-danger/30 px-2 py-1 rounded transition-colors">CLOSE</button>
                  </td>
                </tr>
                 <tr v-if="openTrades.length === 0">
                  <td colspan="8" class="px-4 py-12 text-center text-slate-400 italic text-xs">No open positions active</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </main>

    <!-- Add Market Modal -->
    <div v-if="showAddMarketModal" class="fixed inset-0 z-[100] flex items-center justify-center bg-slate-900/50 backdrop-blur-sm">
      <div class="bg-white border border-slate-200 rounded-xl shadow-2xl w-[500px] max-h-[80vh] flex flex-col">
        <div class="p-4 border-b border-slate-200 flex justify-between items-center">
          <h3 class="text-lg font-bold text-primary">Add New Market</h3>
          <button @click="showAddMarketModal = false" class="text-slate-400 hover:text-primary">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        
        <div class="p-4 border-b border-slate-200 space-y-3">
          <input 
            v-model="marketSearchQuery" 
            type="text" 
            placeholder="Search symbol (e.g. BTC, Gold, US30)..." 
            class="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-2 text-primary focus:border-accent outline-none"
          >
          
          <div class="flex flex-wrap gap-2">
            <button 
              v-for="cat in ['ALL', 'FOREX', 'CRYPTO', 'INDICES', 'COMMODITY', 'STOCK']" 
              :key="cat"
              @click="selectedCategory = cat"
              class="px-3 py-1 text-[10px] font-bold rounded-full border transition-all"
              :class="selectedCategory === cat ? 'bg-accent text-white border-accent' : 'bg-slate-50 text-slate-500 border-slate-200 hover:border-slate-300'"
            >
              {{ cat }}
            </button>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto p-2 custom-scrollbar">
          <div v-if="loadingMarkets" class="text-center py-8 text-slate-500">
            <div class="animate-spin inline-block w-6 h-6 border-2 border-accent border-t-transparent rounded-full mb-2"></div>
            <div>Loading symbols from broker...</div>
          </div>
          
          <div v-else-if="filteredMarkets.length === 0" class="text-center py-8 text-slate-500">
            No symbols found matching "{{ marketSearchQuery }}"
          </div>

          <div v-else class="grid grid-cols-1 gap-1">
            <button 
              v-for="market in filteredMarkets" 
              :key="market.symbol"
              @click="selectNewMarket(market)"
              class="flex items-center justify-between p-3 hover:bg-slate-50 rounded-lg group transition-colors text-left"
            >
              <div>
                <div class="font-bold text-primary group-hover:text-accent">{{ market.symbol }}</div>
                <div class="text-xs text-slate-500">{{ market.description }}</div>
              </div>
              <div class="text-xs font-mono px-2 py-1 rounded bg-slate-100 text-slate-500 border border-slate-200">
                {{ market.type.toUpperCase() }}
              </div>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch, computed } from 'vue';
import TradingChart from './TradingChart.vue';
import api from '../services/api';
import ActivityLog from './ActivityLog.vue';
import FundamentalWidget from './FundamentalWidget.vue';

// State
const selectedSymbol = ref('EURUSD');
const selectedTimeframe = ref('H1');
const availableSymbols = ref([]);
const isBotRunning = ref(false);
const signals = ref([]);
const openTrades = ref([]);
const activeTab = ref('signals'); // 'signals' or 'logs'
const currentBotId = ref(null);
const accountInfo = ref(null);
const isSocketConnected = ref(false);
let pollingInterval = null;

// Add Market State
const showAddMarketModal = ref(false);
const marketSearchQuery = ref('');
const availableMarkets = ref([]);
const loadingMarkets = ref(false);
const selectedCategory = ref('ALL');

const filteredMarkets = computed(() => {
  let filtered = availableMarkets.value;

  // Filter by Category
  if (selectedCategory.value !== 'ALL') {
    filtered = filtered.filter(m => m.type.toUpperCase() === selectedCategory.value);
  }

  // Filter by Search
  if (marketSearchQuery.value) {
    const query = marketSearchQuery.value.toLowerCase();
    filtered = filtered.filter(m => 
      m.symbol.toLowerCase().includes(query) || 
      (m.description && m.description.toLowerCase().includes(query))
    );
  }

  return filtered.slice(0, 50); // Limit view
});

const openAddMarketModal = async () => {
  showAddMarketModal.value = true;
  if (availableMarkets.value.length === 0) {
    loadingMarkets.value = true;
    try {
      const data = await api.getAvailableSymbols();
      if (data.symbols) {
        availableMarkets.value = data.symbols;
      }
    } catch (e) {
      console.error("Failed to load markets:", e);
      alert("Failed to load symbols from broker");
    } finally {
      loadingMarkets.value = false;
    }
  }
};

const selectNewMarket = async (market) => {
  if (!confirm(`Add ${market.symbol} (${market.type}) to your dashboard?`)) return;
  
  try {
    // Create new bot config
    // We need a user ID. In a real app, we get it from auth state.
    // For now, we assume user ID 1 or fetch from local storage if available.
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    const userId = user.id || 1; // Fallback to 1

    const newConfig = await api.createBotConfig({
      user_id: userId,
      name: `${market.symbol} Bot`,
      symbol: market.symbol,
      symbol_type: market.type,
      timeframe: 'H1'
    });

    if (newConfig) {
      // Refresh available symbols list
      await loadSymbols();
      // Select the new symbol
      selectedSymbol.value = newConfig.symbol;
      await onSymbolChange();
      
      showAddMarketModal.value = false;
      alert(`${market.symbol} added successfully!`);
    }
  } catch (e) {
    console.error("Failed to add market:", e);
    alert("Failed to add market");
  }
};

const totalPnL = computed(() => {
  return openTrades.value.reduce((sum, trade) => sum + (trade.pnl || 0), 0);
});

const tradingPlan = ref({
  risk_percent: 2.0,
  be_trigger: 1.0,
  trailing_sl: false,
  trailing_step: 1.0,
  trailing_distance: 1.5,
  tsl_mode: 'FIXED',
  tsl_activation_r: 0.0,
  tsl_atr_period: 14,
  tsl_atr_multiplier: 1.5,
  partial_tp_on: false,
  partial_tp_amount: 0.5,
  max_spread: 2.0,
  trading_hours_start: "00:00",
  trading_hours_end: "23:59",
  daily_loss_limit_percent: 3.0
});

// Chart State
const chartData = ref([]); // Raw OHLCV data for TradingChart
const isDark = ref(false); // Changed to false for light theme

// Methods
const loadSymbols = async () => {
  try {
    const data = await api.getSymbols();
    if (data.symbols) {
      availableSymbols.value = data.symbols;
      // Set initial symbol if available
      if (availableSymbols.value.length > 0) {
        selectedSymbol.value = availableSymbols.value[0].symbol;
        selectedTimeframe.value = availableSymbols.value[0].timeframe || 'H1';
      }
    }
  } catch (e) { console.error(e); }
};

const findBotConfig = async () => {
  try {
    const bots = await api.getBots();
    const bot = bots.find(b => b.symbol === selectedSymbol.value);
    if (bot) {
      currentBotId.value = bot.id;
      selectedTimeframe.value = bot.timeframe;
      
      // Check status
      const status = await api.getBotStatus(bot.id);
      isBotRunning.value = status.is_running;
      
      // Load config
      await loadConfig(bot.id);
    } else {
      currentBotId.value = null;
      isBotRunning.value = false;
    }
  } catch (e) { console.error("Error finding bot:", e); }
};

const loadConfig = async (botId) => {
  try {
    const config = await api.getBotConfig(botId);
    if (config) {
      tradingPlan.value = {
        risk_percent: config.risk_percent,
        be_trigger: config.be_trigger,
        trailing_sl: config.trailing_sl,
        trailing_step: config.trailing_step,
        trailing_distance: config.trailing_distance || 1.5,
        tsl_mode: config.tsl_mode || 'FIXED',
        tsl_activation_r: config.tsl_activation_r || 0.0,
        tsl_atr_period: config.tsl_atr_period || 14,
        tsl_atr_multiplier: config.tsl_atr_multiplier || 1.5,
        partial_tp_on: config.partial_tp_on,
        partial_tp_amount: config.partial_tp_amount,
        max_spread: config.max_spread,
        trading_hours_start: config.trading_hours_start,
        trading_hours_end: config.trading_hours_end,
        daily_loss_limit_percent: config.daily_loss_limit_percent
      };
    }
  } catch (e) { console.error("Error loading config:", e); }
};

const saveConfig = async () => {
  if (!currentBotId.value) return;
  try {
    const updatedConfig = await api.updateBotConfig(currentBotId.value, tradingPlan.value);
    if (updatedConfig) {
      // Update local state with confirmed data from backend
      tradingPlan.value = {
        risk_percent: updatedConfig.risk_percent,
        be_trigger: updatedConfig.be_trigger,
        trailing_sl: updatedConfig.trailing_sl,
        trailing_step: updatedConfig.trailing_step,
        trailing_distance: updatedConfig.trailing_distance,
        tsl_mode: updatedConfig.tsl_mode,
        tsl_activation_r: updatedConfig.tsl_activation_r,
        tsl_atr_period: updatedConfig.tsl_atr_period,
        tsl_atr_multiplier: updatedConfig.tsl_atr_multiplier,
        partial_tp_on: updatedConfig.partial_tp_on,
        partial_tp_amount: updatedConfig.partial_tp_amount,
        max_spread: updatedConfig.max_spread,
        trading_hours_start: updatedConfig.trading_hours_start,
        trading_hours_end: updatedConfig.trading_hours_end,
        daily_loss_limit_percent: updatedConfig.daily_loss_limit_percent
      };
      alert("Configuration Saved!");
    }
  } catch (e) {
    console.error("Error saving config:", e);
    alert("Failed to save configuration");
  }
};

const fetchSignals = async () => {
  try {
    const data = await api.getSignals(selectedSymbol.value);
    if (data.signals) signals.value = data.signals;
  } catch (e) { console.error(e); }
};

const fetchTrades = async () => {
  try {
    // Use getPositions for real-time data
    const response = await api.getPositions();
    const trades = response.positions || [];
    openTrades.value = trades.map(t => ({
      ticket: t.ticket,
      symbol: t.symbol,
      type: t.type, // Note: getLiveTrades returns 'type' not 'trade_type'
      volume: t.volume,
      entry: t.price_open, // Note: getLiveTrades returns 'price_open'
      current: t.price_current, // Note: getLiveTrades returns 'price_current'
      pnl: t.profit, // Note: getLiveTrades returns 'profit'
      sl: t.sl,
      tp: t.tp
    }));
    updateAnnotations();
  } catch (e) { console.error(e); }
};

const fetchAccountInfo = async () => {
  try {
    const info = await api.getAccountInfo();
    accountInfo.value = info;
  } catch (e) { console.error(e); }
};

const updateAnnotations = () => {
  // TradingChart handles its own markers via props
};

const toggleBot = async () => {
  if (!currentBotId.value) return;
  
  try {
    if (isBotRunning.value) {
      await api.stopBot(currentBotId.value);
      isBotRunning.value = false;
    } else {
      await api.startBot(currentBotId.value);
      isBotRunning.value = true;
    }
  } catch (e) { console.error(e); }
};

const onSymbolChange = async () => {
  await findBotConfig();
  fetchSignals();
  updateChart();
};

const onTimeframeChange = async () => {
  if (currentBotId.value) {
    try {
      await api.updateBotConfig(currentBotId.value, { timeframe: selectedTimeframe.value });
      updateChart();
    } catch (e) {
      console.error("Failed to update timeframe", e);
      alert("Failed to update timeframe");
    }
  }
};

const updateChart = async () => {
  try {
    const data = await api.getMarketHistory(selectedSymbol.value, selectedTimeframe.value);
    if (data.data) {
      chartData.value = data.data;
    }
  } catch (e) {
    console.error("Error updating chart:", e);
  }
};


const executeSignal = async (signal) => {
  if (!confirm(`Execute ${signal.signal_type} on ${signal.symbol}?`)) return;
  
  try {
    await api.openTrade({
      symbol: signal.symbol,
      trade_type: signal.signal_type,
      volume: 0.01, // Default or calc
      stop_loss: signal.stop_loss,
      take_profit_1: signal.take_profit,
      risk_percent: tradingPlan.value.risk_percent,
      confluence_score: signal.confluence_score,
      score_breakdown: signal.score_breakdown
    });
    alert('Trade Executed!');
    fetchSignals(); // Refresh to show executed status
  } catch (e) {
    alert('Execution Failed: ' + e.message);
  }
};

const formatTimeAgo = (iso) => {
  if (!iso) return '';
  const date = new Date(iso);
  const diff = (new Date() - date) / 1000;
  if (diff < 60) return `${Math.floor(diff)}s ago`;
  if (diff < 3600) return `${Math.floor(diff/60)}m ago`;
  return `${Math.floor(diff/3600)}h ago`;
};

const formatCurrency = (val) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(val);

const closeTrade = async (ticket) => {
  if (!confirm(`Close trade ${ticket}?`)) return;
  try {
    await api.closeTrade(ticket);
    alert('Trade Closed');
    fetchTrades(); // Refresh list
  } catch (e) {
    alert('Failed to close trade: ' + e.message);
  }
};

const moveToBE = async (ticket) => {
  if (!confirm(`Move trade ${ticket} to Break Even?`)) return;
  try {
    await api.moveToBE(ticket);
    alert('Moved to Break Even');
  } catch (e) {
    alert('Failed to move to BE: ' + e.message);
  }
};

const clearSignals = async () => {
  if (!confirm('Clear all signals?')) return;
  try {
    await api.clearSignals();
    signals.value = []; // Optimistic update
  } catch (e) {
    console.error(e);
    alert('Failed to clear signals');
  }
};

const trailSL = async (ticket) => {
  try {
    await api.trailSL(ticket);
    alert('SL Trailed');
  } catch (e) {
    alert('Failed to trail SL: ' + (e.response?.data?.detail || e.message));
  }
};

// Lifecycle
let socket;

onMounted(async () => {
  await loadSymbols();
  await findBotConfig(); // Load initial bot config
  fetchSignals();
  updateChart();
  fetchTrades();
  fetchAccountInfo();
  
  // Initialize Socket.IO
  socket = api.getSocket();
  
  if (socket) {
    // Check if already connected
    if (socket.connected) {
      console.log('Socket already connected');
      isSocketConnected.value = true;
    }

    socket.on('connect', () => {
      console.log('Socket Connected');
      isSocketConnected.value = true;
    });

    socket.on('disconnect', () => {
      console.log('Socket Disconnected');
      isSocketConnected.value = false;
    });

    // Real-time Market Data (Replaces Polling)
    socket.on('market_update', (data) => {
      console.log('Market Update Received:', data); // Debug Log
      
      // Update Account Info
      if (data.account) {
        accountInfo.value = data.account;
      }
      
      // Update Positions
      if (data.positions) {
        openTrades.value = data.positions.map(t => ({
          ticket: t.ticket,
          symbol: t.symbol,
          type: t.type,
          volume: t.volume,
          entry: t.price_open,
          current: t.price_current,
          pnl: t.profit,
          sl: t.sl,
          tp: t.tp
        }));
        updateAnnotations();
        
        // Refresh chart to show latest price action and annotations
        try {
            updateChart();
        } catch (e) {
            console.error("Chart update failed during socket event", e);
        }
      }
    });

    socket.on('signal_generated', (signal) => {
      // Only add if matches selected symbol
      if (signal.symbol === selectedSymbol.value) {
        signals.value.unshift({
          ...signal,
          id: Date.now(),
          was_executed: false
        });
      }
    });

    socket.on('trade_opened', (trade) => {
      // Optional: We get this via market_update now, but good for immediate notification
      console.log("Trade opened:", trade.ticket);
    });
  }
});

onUnmounted(() => {
  if (socket) {
    socket.off('market_update');
    socket.off('signal_generated');
    socket.off('trade_opened');
    socket.disconnect();
  }
});
</script>
