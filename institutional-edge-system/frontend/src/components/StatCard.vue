<template>
  <div class="card">
    <div class="card-body">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-gray-400 text-sm mb-1">{{ title }}</div>
          <div :class="['text-2xl font-bold', valueClass]">
            {{ value }}
          </div>
        </div>
        <div class="text-4xl opacity-50">{{ icon }}</div>
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
