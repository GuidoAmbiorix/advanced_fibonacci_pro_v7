<template>
  <div class="card">
    <div class="card-header">
      <h2 class="text-xl font-bold">🏗️ Market Structure</h2>
    </div>

    <div class="card-body">
      <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
        <!-- Active Order Blocks -->
        <div class="p-4 bg-gray-700/50 rounded">
          <div class="text-sm text-gray-400 mb-1">Order Blocks</div>
          <div class="text-2xl font-bold text-blue-400">{{ activeOrderBlocks }}</div>
          <div class="text-xs text-gray-500">Active zones</div>
        </div>

        <!-- Active FVGs -->
        <div class="p-4 bg-gray-700/50 rounded">
          <div class="text-sm text-gray-400 mb-1">Fair Value Gaps</div>
          <div class="text-2xl font-bold text-purple-400">{{ activeFvgs }}</div>
          <div class="text-xs text-gray-500">Unfilled gaps</div>
        </div>

        <!-- Premium/Discount -->
        <div class="p-4 bg-gray-700/50 rounded">
          <div class="text-sm text-gray-400 mb-1">Zone</div>
          <div
            class="text-2xl font-bold"
            :class="premiumDiscount.zone === 'PREMIUM' ? 'text-red-400' : 'text-green-400'"
          >
            {{ premiumDiscount.zone || 'NEUTRAL' }}
          </div>
          <div class="text-xs text-gray-500">Current zone</div>
        </div>
      </div>

      <!-- Volume Profile Levels -->
      <div v-if="pocLevel" class="mt-6 space-y-3">
        <div class="text-sm font-semibold text-gray-300 mb-3">Volume Profile Levels</div>

        <div class="flex items-center justify-between p-3 bg-yellow-900/20 border border-yellow-600 rounded">
          <div class="flex items-center space-x-3">
            <div class="w-2 h-2 bg-yellow-500 rounded-full"></div>
            <span class="font-medium">POC (Point of Control)</span>
          </div>
          <span class="font-mono text-yellow-400">{{ pocLevel.toFixed(5) }}</span>
        </div>

        <div v-if="vahLevel" class="flex items-center justify-between p-3 bg-orange-900/20 border border-orange-600 rounded">
          <div class="flex items-center space-x-3">
            <div class="w-2 h-2 bg-orange-500 rounded-full"></div>
            <span class="font-medium">VAH (Value Area High)</span>
          </div>
          <span class="font-mono text-orange-400">{{ vahLevel.toFixed(5) }}</span>
        </div>

        <div v-if="valLevel" class="flex items-center justify-between p-3 bg-orange-900/20 border border-orange-600 rounded">
          <div class="flex items-center space-x-3">
            <div class="w-2 h-2 bg-orange-500 rounded-full"></div>
            <span class="font-medium">VAL (Value Area Low)</span>
          </div>
          <span class="font-mono text-orange-400">{{ valLevel.toFixed(5) }}</span>
        </div>

        <div v-if="premiumDiscount.equilibrium" class="flex items-center justify-between p-3 bg-gray-700/50 border border-gray-600 rounded">
          <div class="flex items-center space-x-3">
            <div class="w-2 h-2 bg-gray-400 rounded-full"></div>
            <span class="font-medium">Equilibrium (50%)</span>
          </div>
          <span class="font-mono text-gray-400">{{ premiumDiscount.equilibrium.toFixed(5) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  activeOrderBlocks: {
    type: Number,
    default: 0
  },
  activeFvgs: {
    type: Number,
    default: 0
  },
  pocLevel: {
    type: Number,
    default: null
  },
  vahLevel: {
    type: Number,
    default: null
  },
  valLevel: {
    type: Number,
    default: null
  },
  premiumDiscount: {
    type: Object,
    default: () => ({})
  }
})
</script>
