<template>
  <div class="slot-grid-container">
    <!-- Header with Grid Controls (cleaner layout) -->
    <div class="grid-header">
      <div class="flex items-center justify-between">
        <h2 class="text-2xl font-bold text-white">Trading Slots</h2>
        <div class="flex items-center gap-4">
          <!-- Layout Pills (more compact) -->
          <div class="layout-pills">
            <button
              v-for="layout in layouts"
              :key="layout.id"
              @click="selectedLayout = layout.id"
              :class="['layout-pill', { active: selectedLayout === layout.id }]"
            >
              {{ layout.label }}
            </button>
          </div>
          <button @click="showSlotSelector = !showSlotSelector" class="select-slots-btn">
            <SlidersHorizontal class="w-4 h-4" />
            Select Slots ({{ selectedSlots.length }})
          </button>
        </div>
      </div>

      <!-- Collapsible Slot Selector -->
      <transition name="slide-down">
        <div v-if="showSlotSelector" class="slot-selector-panel">
          <div class="flex items-center justify-between mb-3">
            <span class="text-sm text-gray-400">
              Select up to {{ maxSlots }} slots
            </span>
            <button @click="clearSelection" class="text-xs text-red-400 hover:text-red-300">
              Clear All
            </button>
          </div>
          <div class="slot-chips">
            <label
              v-for="slot in availableSlots"
              :key="slot.id"
              :class="['slot-chip', {
                selected: selectedSlots.includes(slot.id),
                disabled: selectedSlots.length >= maxSlots && !selectedSlots.includes(slot.id)
              }]"
            >
              <input
                type="checkbox"
                :value="slot.id"
                v-model="selectedSlots"
                :disabled="selectedSlots.length >= maxSlots && !selectedSlots.includes(slot.id)"
                class="hidden"
              />
              <span class="chip-content">
                <span class="font-semibold">{{ slot.symbol }}</span>
                <span class="text-xs opacity-75">{{ slot.timeframe }}</span>
                <span
                  class="status-indicator"
                  :class="{ active: slot.enabled }"
                ></span>
              </span>
            </label>
          </div>
        </div>
      </transition>
    </div>

    <!-- Slot Grid with better spacing -->
    <div :class="['slot-grid', `layout-${selectedLayout}`]">
      <MiniSlotCard
        v-for="slotId in selectedSlots.slice(0, maxSlots)"
        :key="slotId"
        :slot-id="slotId"
        @expand="expandSlot"
      />
    </div>

    <!-- Improved Modal -->
    <Teleport to="body">
      <transition name="modal">
        <div v-if="expandedSlotId" class="modal-backdrop" @click="closeModal">
          <div class="modal-container" @click.stop>
            <!-- Sticky Header -->
            <div class="modal-header">
              <div class="flex items-center gap-3">
                <div class="icon-badge">⚙️</div>
                <div>
                  <h3 class="text-xl font-bold text-white">
                    {{ editingSlot.symbol }}
                  </h3>
                  <p class="text-sm text-gray-400">{{ editingSlot.timeframe }} Configuration</p>
                </div>
              </div>
              <button @click="closeModal" class="close-btn">
                <X class="w-5 h-5" />
              </button>
            </div>

            <!-- Improved Tabs with Icons -->
            <div class="modal-tabs">
              <button
                v-for="tab in tabs"
                :key="tab.id"
                @click="currentTab = tab.id"
                :class="['tab-button', { active: currentTab === tab.id }]"
              >
                <component :is="tab.icon" class="w-4 h-4" />
                <span>{{ tab.label }}</span>
              </button>
            </div>

            <!-- Content with better organization -->
            <div class="modal-body">
              <!-- Content sections with cards -->
              <transition name="fade" mode="out-in">
                <div :key="currentTab" class="tab-content">
                  
                  <!-- GENERAL TAB -->
                  <div v-if="currentTab === 'general'" class="space-y-6">
                    <!-- Status Card -->
                    <div class="config-card">
                      <div class="card-header">
                        <h4 class="card-title">Basic Settings</h4>
                      </div>
                      <div class="card-body">
                        <div class="grid grid-cols-2 gap-4">
                          <div class="form-field">
                            <label>Symbol</label>
                            <input v-model="editingSlot.symbol" disabled class="input-disabled" />
                          </div>
                          <div class="form-field">
                            <label>Timeframe</label>
                            <select v-model="editingSlot.timeframe" class="input-select">
                              <option value="M1">M1 - 1 Minute</option>
                              <option value="M5">M5 - 5 Minutes</option>
                              <option value="M15">M15 - 15 Minutes</option>
                              <option value="H1">H1 - 1 Hour</option>
                              <option value="H4">H4 - 4 Hours</option>
                            </select>
                          </div>
                          <div class="form-field">
                            <label>Direction</label>
                            <div class="direction-buttons">
                              <button
                                v-for="dir in ['BOTH', 'LONG', 'SHORT']"
                                :key="dir"
                                @click="editingSlot.direction_filter = dir"
                                :class="['direction-btn', { active: editingSlot.direction_filter === dir }]"
                              >
                                {{ dir }}
                              </button>
                            </div>
                          </div>
                          <div class="form-field">
                            <label>Status</label>
                            <div class="toggle-switch">
                              <input
                                v-model="editingSlot.enabled"
                                type="checkbox"
                                class="toggle-input"
                                id="slot-enabled"
                              />
                              <label for="slot-enabled" class="toggle-label">
                                <span class="toggle-slider"></span>
                              </label>
                              <span :class="['toggle-text', { active: editingSlot.enabled }]">
                                {{ editingSlot.enabled ? 'ENABLED' : 'DISABLED' }}
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>

                    <!-- Risk Card -->
                    <div class="config-card accent-blue">
                      <div class="card-header">
                        <h4 class="card-title">💰 Risk Management</h4>
                      </div>
                      <div class="card-body">
                        <div class="grid grid-cols-3 gap-4">
                          <div class="form-field">
                            <label>Risk per Trade</label>
                            <div class="input-with-suffix">
                              <input
                                v-model.number="editingSlot.risk_percent"
                                type="number"
                                step="0.1"
                                class="input-number"
                              />
                              <span class="suffix">%</span>
                            </div>
                          </div>
                          <div class="form-field">
                            <label>Take Profit Ratio</label>
                            <div class="input-with-suffix">
                              <input
                                v-model.number="editingSlot.tp_ratio"
                                type="number"
                                step="0.1"
                                class="input-number"
                              />
                              <span class="suffix">R</span>
                            </div>
                          </div>
                          <div class="form-field">
                            <label>SL Multiplier</label>
                            <div class="input-with-suffix">
                              <input
                                v-model.number="editingSlot.sl_atr_multiplier"
                                type="number"
                                step="0.1"
                                class="input-number"
                              />
                              <span class="suffix">× ATR</span>
                            </div>
                          </div>
                        </div>
                        <!-- Risk Preview -->
                        <div class="risk-preview">
                          <div class="risk-stat">
                            <span class="stat-label">Expected Loss</span>
                            <span class="stat-value text-red-400">
                              -${{ (editingSlot.risk_percent * 100).toFixed(2) }}
                            </span>
                          </div>
                          <div class="risk-stat">
                            <span class="stat-label">Expected Gain</span>
                            <span class="stat-value text-green-400">
                              +${{ (editingSlot.risk_percent * editingSlot.tp_ratio * 100).toFixed(2) }}
                            </span>
                          </div>
                          <div class="risk-stat">
                            <span class="stat-label">Risk:Reward</span>
                            <span class="stat-value text-blue-400">
                              1:{{ editingSlot.tp_ratio }}
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- SESSION TAB (improved) -->
                  <div v-if="currentTab === 'session'" class="space-y-6">
                    <div class="config-card accent-purple">
                      <div class="card-header">
                        <h4 class="card-title">🕒 Trading Sessions</h4>
                        <span class="badge badge-purple">Active: {{ editingSlot.trading_session }}</span>
                      </div>
                      <div class="card-body">
                        <!-- Visual Session Selector -->
                        <div class="session-selector">
                          <button
                            v-for="session in sessions"
                            :key="session.value"
                            @click="editingSlot.trading_session = session.value"
                            :class="['session-card', {
                              active: editingSlot.trading_session === session.value
                            }]"
                          >
                            <div class="session-icon">{{ session.icon }}</div>
                            <div class="session-info">
                              <div class="session-name">{{ session.label }}</div>
                              <div class="session-time">{{ session.time }}</div>
                            </div>
                            <div v-if="editingSlot.trading_session === session.value" class="check-icon">
                              ✓
                            </div>
                          </button>
                        </div>

                        <div class="grid grid-cols-2 gap-4 mt-6">
                          <div class="form-field">
                            <label>End of Session Action</label>
                            <select v-model="editingSlot.session_end_action" class="input-select">
                              <option value="HOLD">📊 Hold Positions</option>
                              <option value="CLOSE">❌ Close All Trades</option>
                              <option value="BE">🎯 Move to Breakeven</option>
                            </select>
                          </div>
                          <div class="form-field">
                            <label>Daily Bias Filter</label>
                            <div class="toggle-switch">
                              <input
                                v-model="editingSlot.use_daily_bias"
                                type="checkbox"
                                class="toggle-input"
                                id="daily-bias"
                              />
                              <label for="daily-bias" class="toggle-label">
                                <span class="toggle-slider"></span>
                              </label>
                              <span class="toggle-text">
                                {{ editingSlot.use_daily_bias ? 'ON' : 'OFF' }}
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- STRATEGY TAB (cards with toggle switches) -->
                  <div v-if="currentTab === 'strategy'" class="space-y-4">
                    <div class="config-card">
                      <div class="card-header">
                        <h4 class="card-title">Strategy Modules</h4>
                      </div>
                      <div class="card-body space-y-3">
                        <div
                          v-for="strategy in strategies"
                          :key="strategy.key"
                          class="strategy-toggle"
                        >
                          <div class="flex-1">
                            <div class="flex items-center gap-2 mb-1">
                              <span class="text-lg">{{ strategy.icon }}</span>
                              <span class="font-semibold text-white">{{ strategy.name }}</span>
                              <span v-if="strategy.premium" class="badge badge-gold">PRO</span>
                            </div>
                            <p class="text-sm text-gray-400">{{ strategy.description }}</p>
                          </div>
                          <div class="toggle-switch">
                            <input
                              v-model="editingSlot[strategy.key]"
                              type="checkbox"
                              class="toggle-input"
                              :id="strategy.key"
                            />
                            <label :for="strategy.key" class="toggle-label">
                              <span class="toggle-slider"></span>
                            </label>
                          </div>
                        </div>
                      </div>
                    </div>

                    <!-- Filters Card -->
                    <div class="config-card">
                      <div class="card-header">
                        <h4 class="card-title">🎯 Filters & Confluence</h4>
                      </div>
                      <div class="card-body space-y-4">
                        <div class="strategy-toggle">
                          <span class="font-medium">ADX Trend Filter (>25)</span>
                          <div class="toggle-switch">
                            <input
                              v-model="editingSlot.use_adx_filter"
                              type="checkbox"
                              class="toggle-input"
                              id="adx-filter"
                            />
                            <label for="adx-filter" class="toggle-label">
                              <span class="toggle-slider"></span>
                            </label>
                          </div>
                        </div>

                        <div class="form-field">
                          <div class="flex justify-between items-center mb-2">
                            <label>Minimum Confluence Score</label>
                            <span class="badge badge-blue">{{ editingSlot.min_confluence_score }}</span>
                          </div>
                          <input
                            v-model.number="editingSlot.min_confluence_score"
                            type="range"
                            min="3"
                            max="10"
                            class="range-slider"
                          />
                          <div class="flex justify-between text-xs text-gray-500 mt-1">
                            <span>3 (Low)</span>
                            <span>10 (High)</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>

                </div>
              </transition>
            </div>

            <!-- Sticky Footer -->
            <div class="modal-footer">
              <button @click="resetChanges" class="btn-secondary">
                Reset Changes
              </button>
              <div class="flex gap-3">
                <button @click="closeModal" class="btn-ghost">
                  Cancel
                </button>
                <button @click="saveSlotConfig" class="btn-primary">
                  <Save class="w-4 h-4" />
                  Save Configuration
                </button>
              </div>
            </div>
          </div>
        </div>
      </transition>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
// Add to your existing imports
import { Save, X, SlidersHorizontal } from 'lucide-vue-next'

const showSlotSelector = ref(false)

const sessions = [
  { value: 'ALL', label: 'All Day', icon: '🌍', time: '24/7' },
  { value: 'LONDON_KZ', label: 'London', icon: '🇬🇧', time: '07:00-10:00 UTC' },
  { value: 'NY_KZ', label: 'New York', icon: '🇺🇸', time: '12:00-15:00 UTC' },
  { value: 'BOTH_KZ', label: 'London + NY', icon: '🌐', time: 'Both Sessions' }
]

const strategies = [
  {
    key: 'enable_vwap_strategy',
    name: 'VWAP Scalp',
    icon: '📊',
    description: 'Volume-weighted average price mean reversion',
    premium: false
  },
  {
    key: 'enable_stoch_strategy',
    name: 'Stochastic Momentum',
    icon: '⚡',
    description: 'Overbought/oversold momentum reversals',
    premium: false
  },
  {
    key: 'enable_institutional_strategy',
    name: 'Institutional Sweep',
    icon: '💎',
    description: 'Smart money liquidity grab detection',
    premium: true
  },
  {
    key: 'enable_fibonacci_strategy',
    name: 'Fibonacci Retracements',
    icon: '📐',
    description: 'Key retracement level entries',
    premium: true
  }
]

const tabs = [
  { id: 'general', label: 'General', icon: 'Settings' },
  { id: 'session', label: 'Sessions', icon: 'Clock' },
  { id: 'indicators', label: 'Indicators', icon: 'TrendingUp' },
  { id: 'strategy', label: 'Strategy', icon: 'Target' },
  { id: 'smc', label: 'SMC', icon: 'Layers' },
  { id: 'management', label: 'Management', icon: 'Shield' }
]

function clearSelection() {
  selectedSlots.value = []
}

function closeModal() {
  expandedSlotId.value = null
}

function resetChanges() {
  const original = availableSlots.value.find(s => s.id === editingSlot.value.id)
  if (original) {
    editingSlot.value = JSON.parse(JSON.stringify(original))
  }
}
</script>

<style scoped>
/* Modern Design System */
.slot-grid-container {
  @apply p-6 space-y-6;
}

.grid-header {
  @apply bg-gradient-to-br from-gray-900 to-gray-800 rounded-2xl p-6 border border-gray-700 space-y-4;
}

/* Layout Pills */
.layout-pills {
  @apply flex bg-gray-800 rounded-lg p-1 gap-1;
}

.layout-pill {
  @apply px-4 py-2 rounded-md text-sm font-medium transition-all;
  @apply text-gray-400 hover:text-white hover:bg-gray-700;
}

.layout-pill.active {
  @apply bg-blue-600 text-white shadow-lg;
}

.select-slots-btn {
  @apply flex items-center gap-2 px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg;
  @apply text-sm font-medium text-white transition-colors;
}

/* Slot Selector Panel */
.slot-selector-panel {
  @apply mt-4 p-4 bg-gray-800/50 rounded-lg border border-gray-700;
}

.slot-chips {
  @apply flex flex-wrap gap-2;
}

.slot-chip {
  @apply px-4 py-2 rounded-lg border-2 cursor-pointer transition-all;
  @apply bg-gray-800 border-gray-600 hover:border-gray-500;
}

.slot-chip.selected {
  @apply bg-blue-600/20 border-blue-500 ring-2 ring-blue-500/50;
}

.slot-chip.disabled {
  @apply opacity-40 cursor-not-allowed;
}

.chip-content {
  @apply flex items-center gap-2 text-sm;
}

.status-indicator {
  @apply w-2 h-2 rounded-full bg-gray-500;
}

.status-indicator.active {
  @apply bg-green-500 shadow-lg shadow-green-500/50;
}

/* Slot Grid */
.slot-grid {
  @apply gap-4;
}

.layout-2x2 {
  @apply grid grid-cols-2;
}

.layout-2x3 {
  @apply grid grid-cols-2 grid-rows-3;
}

.layout-3x3 {
  @apply grid grid-cols-3;
}

/* Modal */
.modal-backdrop {
  @apply fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50 p-4;
}

.modal-container {
  @apply bg-gray-900 rounded-2xl shadow-2xl border border-gray-700 w-full max-w-4xl;
  @apply flex flex-col max-h-[90vh];
}

.modal-header {
  @apply flex items-center justify-between p-6 border-b border-gray-700 sticky top-0 bg-gray-900 z-10 rounded-t-2xl;
}

.icon-badge {
  @apply w-12 h-12 rounded-xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-2xl;
}

.close-btn {
  @apply p-2 hover:bg-gray-800 rounded-lg transition-colors text-gray-400 hover:text-white;
}

.modal-tabs {
  @apply flex gap-2 px-6 pt-4 border-b border-gray-700 overflow-x-auto;
  @apply scrollbar-thin scrollbar-thumb-gray-600 scrollbar-track-gray-800;
}

.tab-button {
  @apply flex items-center gap-2 px-4 py-3 rounded-t-lg transition-all whitespace-nowrap;
  @apply text-gray-400 hover:text-white hover:bg-gray-800;
}

.tab-button.active {
  @apply text-blue-400 bg-gray-800 border-b-2 border-blue-500;
}

.modal-body {
  @apply flex-1 overflow-y-auto p-6;
  @apply scrollbar-thin scrollbar-thumb-gray-600 scrollbar-track-gray-800;
}

.tab-content {
  @apply animate-in fade-in duration-200;
}

.modal-footer {
  @apply flex items-center justify-between p-6 border-t border-gray-700 sticky bottom-0 bg-gray-900 rounded-b-2xl;
}

/* Config Cards */
.config-card {
  @apply bg-gray-800/50 rounded-xl border border-gray-700 overflow-hidden;
}

.config-card.accent-blue {
  @apply border-blue-500/30 bg-blue-950/20;
}

.config-card.accent-purple {
  @apply border-purple-500/30 bg-purple-950/20;
}

.card-header {
  @apply px-6 py-4 bg-gray-800/50 border-b border-gray-700 flex items-center justify-between;
}

.card-title {
  @apply text-base font-bold text-white;
}

.card-body {
  @apply p-6;
}

/* Form Fields */
.form-field {
  @apply space-y-2;
}

label {
  @apply block text-xs font-semibold text-gray-400 uppercase tracking-wider;
}

.input-select,
.input-number {
  @apply w-full px-4 py-2.5 bg-gray-900 border border-gray-600 rounded-lg;
  @apply text-white text-sm focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20;
  @apply transition-all outline-none;
}

.input-disabled {
  @apply w-full px-4 py-2.5 bg-gray-900/50 border border-gray-700 rounded-lg;
  @apply text-gray-500 cursor-not-allowed;
}

.input-with-suffix {
  @apply relative;
}

.input-with-suffix .suffix {
  @apply absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 text-sm font-medium;
}

/* Direction Buttons */
.direction-buttons {
  @apply flex gap-2;
}

.direction-btn {
  @apply flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-all;
  @apply bg-gray-700 text-gray-300 hover:bg-gray-600;
}

.direction-btn.active {
  @apply bg-blue-600 text-white shadow-lg;
}

/* Toggle Switch (iOS style) */
.toggle-switch {
  @apply flex items-center gap-3;
}

.toggle-input {
  @apply hidden;
}

.toggle-label {
  @apply relative w-12 h-6 bg-gray-700 rounded-full cursor-pointer transition-colors;
}

.toggle-slider {
  @apply absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full transition-transform;
}

.toggle-input:checked + .toggle-label {
  @apply bg-blue-600;
}

.toggle-input:checked + .toggle-label .toggle-slider {
  @apply translate-x-6;
}

.toggle-text {
  @apply text-sm font-medium text-gray-400;
}

.toggle-text.active {
  @apply text-blue-400;
}

/* Session Selector */
.session-selector {
  @apply grid grid-cols-2 gap-3;
}

.session-card {
  @apply relative p-4 bg-gray-800 rounded-lg border-2 border-gray-700;
  @apply hover:border-gray-600 transition-all cursor-pointer;
}

.session-card.active {
  @apply border-purple-500 bg-purple-950/30 ring-2 ring-purple-500/30;
}

.session-icon {
  @apply text-2xl mb-2;
}

.session-info {
  @apply text-left;
}

.session-name {
  @apply font-semibold text-white mb-1;
}

.session-time {
  @apply text-xs text-gray-400;
}

.check-icon {
  @apply absolute top-2 right-2 w-6 h-6 bg-purple-600 rounded-full;
  @apply flex items-center justify-center text-white text-xs font-bold;
}

/* Strategy Toggle */
.strategy-toggle {
  @apply flex items-center justify-between p-4 bg-gray-800/50 rounded-lg;
  @apply hover:bg-gray-800 transition-colors;
}

/* Risk Preview */
.risk-preview {
  @apply grid grid-cols-3 gap-4 mt-4 pt-4 border-t border-gray-700;
}

.risk-stat {
  @apply flex flex-col items-center;
}

.stat-label {
  @apply text-xs text-gray-400 mb-1;
}

.stat-value {
  @apply text-lg font-bold;
}

/* Badges */
.badge {
  @apply inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium;
}

.badge-purple {
  @apply bg-purple-900/50 text-purple-300 border border-purple-700;
}

.badge-blue {
  @apply bg-blue-900/50 text-blue-300 border border-blue-700;
}

.badge-gold {
  @apply bg-yellow-900/50 text-yellow-300 border border-yellow-700;
}

/* Range Slider */
.range-slider {
  @apply w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer;
}

.range-slider::-webkit-slider-thumb {
  @apply appearance-none w-4 h-4 bg-blue-600 rounded-full cursor-pointer;
  @apply hover:bg-blue-500 transition-colors;
}

/* Buttons */
.btn-primary {
  @apply flex items-center gap-2 px-6 py-2.5 bg-blue-600 hover:bg-blue-500;
  @apply text-white font-semibold rounded-lg transition-colors shadow-lg;
}

.btn-secondary {
  @apply px-6 py-2.5 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors;
}

.btn-ghost {
  @apply px-6 py-2.5 text-gray-300 hover:text-white hover:bg-gray-800 font-medium rounded-lg transition-colors;
}

/* Animations */
.slide-down-enter-active,
.slide-down-leave-active {
  @apply transition-all duration-300;
}

.slide-down-enter-from,
.slide-down-leave-to {
  @apply opacity-0 -translate-y-4;
}

.modal-enter-active,
.modal-leave-active {
  @apply transition-all duration-300;
}

.modal-enter-from,
.modal-leave-to {
  @apply opacity-0;
}

.modal-enter-from .modal-container,
.modal-leave-to .modal-container {
  @apply scale-95 opacity-0;
}

.fade-enter-active,
.fade-leave-active {
  @apply transition-opacity duration-200;
}

.fade-enter-from,
.fade-leave-to {
  @apply opacity-0;
}

/* Custom Scrollbar */
.scrollbar-thin {
  scrollbar-width: thin;
}

.scrollbar-thin::-webkit-scrollbar {
  @apply w-2;
}

.scrollbar-thin::-webkit-scrollbar-track {
  @apply bg-gray-800;
}

.scrollbar-thin::-webkit-scrollbar-thumb {
  @apply bg-gray-600 rounded-full hover:bg-gray-500;
}
</style>
