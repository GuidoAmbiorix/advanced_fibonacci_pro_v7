
<template>
  <div class="slot-grid-container">
    <!-- Grid Controls -->
    <div class="grid-controls">
      <div class="layout-selector">
        <button
          v-for="layout in layouts"
          :key="layout.id"
          @click="selectedLayout = layout.id"
          :class="['layout-btn', { active: selectedLayout === layout.id }]"
        >
          <component :is="layout.icon" class="w-5 h-5" />
          <span class="text-xs">{{ layout.label }}</span>
        </button>
      </div>

      <div class="slot-selector">
        <div class="slot-checkboxes">
          <label
            v-for="slot in availableSlots"
            :key="slot.id"
            class="slot-checkbox"
          >
            <input
              type="checkbox"
              :value="slot.id"
              v-model="selectedSlots"
              :disabled="selectedSlots.length >= maxSlots && !selectedSlots.includes(slot.id)"
            />
            <span>{{ slot.symbol }} ({{ slot.timeframe }})</span>
            <span
              class="status-dot"
              :class="{
                'bg-green-500': slot.enabled,
                'bg-gray-500': !slot.enabled
              }"
            ></span>
          </label>
        </div>
      </div>

      <button @click="saveGridConfig" class="save-btn">
        Save Configuration
      </button>
    </div>

    <!-- Slot Grid -->
    <div
      class="slot-grid"
      :class="`grid-${selectedLayout}`"
    >
      <MiniSlotCard
        v-for="slot in visibleSlots"
        :key="slot.id"
        :slot-data="slot"
        @expand="expandSlot"
      />
    </div>

    <!-- Expanded Slot Modal -->
    <div v-if="expandedSlotId" class="expanded-slot-modal" @click="expandedSlotId = null">
      <div class="modal-content" @click.stop>
        <h3 class="text-xl font-bold text-white mb-4">Slot {{ expandedSlotId }}</h3>
        <p class="text-gray-400">Full chart view would go here</p>
        <button @click="expandedSlotId = null" class="mt-4 px-4 py-2 bg-blue-600 rounded">
          Close
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { Squares2X2Icon, ViewColumnsIcon, TableCellsIcon } from '@heroicons/vue/24/outline'
import MiniSlotCard from './MiniSlotCard.vue'
import api from '@/services/api'

const layouts = [
  { id: '2x2', label: '2×2', icon: Squares2X2Icon, maxSlots: 4 },
  { id: '2x3', label: '2×3', icon: ViewColumnsIcon, maxSlots: 6 },
  { id: '3x3', label: '3×3', icon: TableCellsIcon, maxSlots: 9 }
]

const selectedLayout = ref('2x2')
const selectedSlots = ref([])
const expandedSlotId = ref(null)
const availableSlots = ref([])

const maxSlots = computed(() => {
  const l = layouts.find(l => l.id === selectedLayout.value)
  return l ? l.maxSlots : 4
})

const visibleSlots = computed(() => {
  return selectedSlots.value
    .slice(0, maxSlots.value)
    .map(id => availableSlots.value.find(s => s.id === id))
    .filter(Boolean)
})

onMounted(async () => {
  // Load available slots
  try {
    const slots = await api.getSlots()
    availableSlots.value = slots

    // Auto-select first 4 slots
    selectedSlots.value = availableSlots.value.slice(0, 4).map(s => s.id)
  } catch (error) {
    console.error('Failed to load slots:', error)
  }
})

function expandSlot(slotId) {
  expandedSlotId.value = slotId
}

async function saveGridConfig() {
  try {
    await api.saveGridConfig({
      name: 'My Grid',
      layout: selectedLayout.value,
      slot_ids: selectedSlots.value,
      show_stats: true,
      show_signals: true,
      auto_refresh_interval: 5
    })
    alert('Grid configuration saved!')
  } catch (error) {
    console.error('Failed to save grid config:', error)
    alert('Failed to save configuration')
  }
}
</script>

<style scoped>
.grid-controls {
  @apply bg-gray-800 p-4 rounded-lg mb-4 space-y-4;
}

.layout-selector {
  @apply flex gap-2;
}

.layout-btn {
  @apply flex items-center gap-2 px-4 py-2 bg-gray-700 rounded hover:bg-gray-600 transition-colors text-gray-300;
}

.layout-btn.active {
  @apply bg-blue-600 text-white;
}

.slot-checkboxes {
  @apply grid grid-cols-2 gap-2 mt-2;
}

.slot-checkbox {
  @apply flex items-center gap-2 text-sm text-gray-300;
}

.status-dot {
  @apply w-2 h-2 rounded-full;
}

.slot-grid {
  @apply grid gap-4;
}

.grid-2x2 {
  @apply grid-cols-2 grid-rows-2;
}

.grid-2x3 {
  @apply grid-cols-2 grid-rows-3;
}

.grid-3x3 {
  @apply grid-cols-3 grid-rows-3;
}

.save-btn {
  @apply bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded text-sm font-medium text-white;
}

.expanded-slot-modal {
  @apply fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50;
}

.modal-content {
  @apply bg-gray-800 rounded-lg p-6 max-w-4xl w-full mx-4;
}
</style>
