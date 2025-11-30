<template>
  <div class="card p-4 transition-all duration-300 hover:scale-105 hover:shadow-card-hover group">
    <div class="flex items-center justify-between">
      <div>
        <div class="text-gray-400 text-sm mb-1 uppercase tracking-wider font-semibold">{{ title }}</div>
        <div :class="['text-2xl font-bold drop-shadow-md', valueClass]">
          {{ value }}
        </div>
      </div>
      <div class="text-4xl opacity-50 group-hover:opacity-100 group-hover:scale-110 transition-all duration-300 filter drop-shadow-lg">{{ icon }}</div>
    </div>
  </div>
</template>

<script setup>
defineProps({
  title: {
    type: String,
    required: true
  },
  value: {
    type: [String, Number],
    required: true
  },
  valueClass: {
    type: String,
    default: 'text-white'
  },
  icon: {
    type: String,
    default: '📊'
  }
})
</script>
