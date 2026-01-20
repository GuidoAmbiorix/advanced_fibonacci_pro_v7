<template>
  <div v-if="selectedZone" class="zone-properties-panel">
    <div class="panel-header">
      <h3 class="text-sm font-semibold text-white">Zone Properties</h3>
      <button @click="$emit('close')" class="close-btn">
        <XMarkIcon class="w-4 h-4" />
      </button>
    </div>

    <div class="panel-body">
      <!-- Zone Label -->
      <div class="form-group">
        <label>Label</label>
        <input
          v-model="properties.label"
          type="text"
          placeholder="e.g., Demand Zone"
          class="input"
        />
      </div>

      <!-- Zone Type -->
      <div class="form-group">
        <label>Zone Type</label>
        <select v-model="properties.type" class="select">
          <option value="DEMAND">Demand (Support)</option>
          <option value="SUPPLY">Supply (Resistance)</option>
          <option value="ORDER_BLOCK">Order Block</option>
          <option value="FVG">Fair Value Gap</option>
          <option value="CUSTOM">Custom</option>
        </select>
      </div>

      <!-- Trade Action -->
      <div class="form-group">
        <label>Trade Action</label>
        <select v-model="properties.action" class="select">
          <option value="NEUTRAL">Informational Only</option>
          <option value="BUY_ONLY">Only Buy in This Zone</option>
          <option value="SELL_ONLY">Only Sell in This Zone</option>
          <option value="NO_TRADE">Do Not Trade in Zone</option>
        </select>
      </div>

      <!-- Visual Properties -->
      <div class="form-group">
        <label>Color</label>
        <div class="color-options">
          <button
            v-for="color in predefinedColors"
            :key="color"
            @click="properties.color = color"
            :class="['color-swatch', { active: properties.color === color }]"
            :style="{ backgroundColor: color }"
          ></button>
          <input
            v-model="properties.color"
            type="color"
            class="color-picker-custom"
          />
        </div>
      </div>

      <div class="form-group">
        <label>Opacity: {{ properties.opacity }}%</label>
        <input
          v-model="properties.opacity"
          type="range"
          min="10"
          max="100"
          class="slider"
        />
      </div>

      <!-- Price Levels -->
      <div class="form-group">
        <label>High Price</label>
        <input
          v-model.number="properties.highPrice"
          type="number"
          step="0.00001"
          class="input"
        />
      </div>

      <div class="form-group">
        <label>Low Price</label>
        <input
          v-model.number="properties.lowPrice"
          type="number"
          step="0.00001"
          class="input"
        />
      </div>

      <!-- Notes -->
      <div class="form-group">
        <label>Notes</label>
        <textarea
          v-model="properties.notes"
          rows="3"
          placeholder="Why this zone is important..."
          class="textarea"
        ></textarea>
      </div>

      <!-- Action Buttons -->
      <div class="action-buttons">
        <button @click="saveChanges" class="btn-primary">
          Save Changes
        </button>
        <button @click="deleteZone" class="btn-danger">
          Delete Zone
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { XMarkIcon } from '@heroicons/vue/24/outline'

interface ZoneProperties {
  label: string
  type: 'DEMAND' | 'SUPPLY' | 'ORDER_BLOCK' | 'FVG' | 'CUSTOM'
  action: 'NEUTRAL' | 'BUY_ONLY' | 'SELL_ONLY' | 'NO_TRADE'
  color: string
  opacity: number
  highPrice: number
  lowPrice: number
  notes: string
}

const props = defineProps<{
  selectedZone: any
}>()

const emit = defineEmits(['save', 'delete', 'close'])

const predefinedColors = ['#3B82F6', '#10B981', '#EF4444', '#F59E0B', '#8B5CF6', '#EC4899']

const properties = ref<ZoneProperties>({
  label: '',
  type: 'DEMAND',
  action: 'NEUTRAL',
  color: '#3B82F6',
  opacity: 30,
  highPrice: 0,
  lowPrice: 0,
  notes: ''
})

watch(() => props.selectedZone, (zone) => {
  if (zone) {
    properties.value = { ...zone.properties }
  }
}, { immediate: true })

function saveChanges() {
  emit('save', {
    zoneId: props.selectedZone.id,
    properties: properties.value
  })
}

function deleteZone() {
  if (confirm('Delete this zone?')) {
    emit('delete', props.selectedZone.id)
  }
}
</script>

<style scoped>
.zone-properties-panel {
  @apply bg-gray-800 border border-gray-700 rounded-lg p-4 w-80;
}

.panel-header {
  @apply flex items-center justify-between mb-4 pb-2 border-b border-gray-700;
}

.close-btn {
  @apply p-1 hover:bg-gray-700 rounded text-gray-300;
}

.panel-body {
  @apply space-y-3;
}

.form-group {
  @apply flex flex-col gap-1;
}

.form-group label {
  @apply text-xs font-medium text-gray-400;
}

.input, .select, .textarea {
  @apply bg-gray-700 border border-gray-600 rounded px-2 py-1.5 text-sm text-white;
}

.color-options {
  @apply flex items-center gap-2;
}

.color-swatch {
  @apply w-8 h-8 rounded cursor-pointer border-2 border-transparent transition-all;
}

.color-swatch.active {
  @apply border-white scale-110;
}

.color-picker-custom {
  @apply w-8 h-8 rounded cursor-pointer border border-gray-600;
}

.slider {
  @apply w-full;
}

.action-buttons {
  @apply flex gap-2 mt-4 pt-4 border-t border-gray-700;
}

.btn-primary {
  @apply flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded text-sm font-medium;
}

.btn-danger {
  @apply flex-1 bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded text-sm font-medium;
}
</style>
