<template>
  <div class="card">
    <div class="card-header flex items-center justify-between">
      <h3 class="text-lg font-bold">{{ title }}</h3>
      <div
        class="text-3xl font-bold"
        :class="type === 'bull' ? 'text-green-400' : 'text-red-400'"
      >
        {{ score }}/10
      </div>
    </div>

    <div class="card-body">
      <div v-if="Object.keys(breakdown).length === 0" class="text-center text-gray-500 py-4">
        No factors detected
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="(points, factor) in breakdown"
          :key="factor"
          class="flex items-center justify-between p-3 bg-gray-700/50 rounded"
        >
          <div class="flex items-center space-x-3">
            <div
              class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold"
              :class="type === 'bull' ? 'bg-green-600' : 'bg-red-600'"
            >
              +{{ points }}
            </div>
            <span class="font-medium">{{ factor }}</span>
          </div>

          <div class="flex-1 mx-4">
            <div class="h-2 bg-gray-600 rounded-full overflow-hidden">
              <div
                class="h-full rounded-full transition-all duration-500"
                :class="type === 'bull' ? 'bg-green-500' : 'bg-red-500'"
                :style="{ width: `${(points / 10) * 100}%` }"
              ></div>
            </div>
          </div>

          <span class="text-sm text-gray-400">{{ Math.round((points / 10) * 100) }}%</span>
        </div>
      </div>

      <div class="mt-4 pt-4 border-t border-gray-700">
        <div class="flex items-center justify-between text-sm">
          <span class="text-gray-400">Total Score:</span>
          <span class="text-xl font-bold" :class="type === 'bull' ? 'text-green-400' : 'text-red-400'">
            {{ score }} points
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  title: {
    type: String,
    required: true
  },
  score: {
    type: Number,
    default: 0
  },
  breakdown: {
    type: Object,
    default: () => ({})
  },
  type: {
    type: String,
    required: true,
    validator: (value) => ['bull', 'bear'].includes(value)
  }
})
</script>
