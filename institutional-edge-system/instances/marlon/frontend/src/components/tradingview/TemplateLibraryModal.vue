<template>
  <div class="modal-overlay" @click="$emit('close')">
    <div class="modal-content" @click.stop>
      <div class="modal-header">
        <h3 class="text-lg font-semibold text-white">Template Library</h3>
        <button @click="$emit('close')" class="close-btn">
          <XMarkIcon class="w-5 h-5" />
        </button>
      </div>

      <div class="modal-body">
        <div v-if="templates.length === 0" class="empty-state">
          <ChartBarIcon class="w-12 h-12 text-gray-500 mx-auto mb-2" />
          <p class="text-gray-400">No templates saved yet</p>
        </div>

        <div v-else class="template-list">
          <div
            v-for="template in templates"
            :key="template.id"
            class="template-item"
          >
            <div class="template-info">
              <h4 class="template-name">{{ template.template_name }}</h4>
              <p class="template-desc">{{ template.description || 'No description' }}</p>
              <span class="template-meta">{{ template.annotations.length }} annotations</span>
            </div>

            <div class="template-actions">
              <button @click="$emit('load', template)" class="btn-load">
                Load
              </button>
              <button @click="$emit('delete', template.id)" class="btn-delete">
                <TrashIcon class="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { XMarkIcon, TrashIcon, ChartBarIcon } from '@heroicons/vue/24/outline'

defineProps<{
  templates: any[]
}>()

defineEmits(['load', 'delete', 'close'])
</script>

<style scoped>
.modal-overlay {
  @apply fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50;
}

.modal-content {
  @apply bg-gray-800 rounded-lg border border-gray-700 w-full max-w-2xl max-h-[80vh] overflow-hidden flex flex-col;
}

.modal-header {
  @apply flex items-center justify-between p-4 border-b border-gray-700;
}

.close-btn {
  @apply p-1 hover:bg-gray-700 rounded text-gray-300;
}

.modal-body {
  @apply p-4 overflow-y-auto;
}

.empty-state {
  @apply text-center py-12;
}

.template-list {
  @apply space-y-2;
}

.template-item {
  @apply flex items-center justify-between p-3 bg-gray-700 rounded border border-gray-600 hover:border-blue-500 transition-colors;
}

.template-info {
  @apply flex-1;
}

.template-name {
  @apply font-semibold text-white;
}

.template-desc {
  @apply text-sm text-gray-400 mt-1;
}

.template-meta {
  @apply text-xs text-gray-500 mt-1 inline-block;
}

.template-actions {
  @apply flex items-center gap-2;
}

.btn-load {
  @apply px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm font-medium;
}

.btn-delete {
  @apply p-2 text-red-400 hover:bg-red-900/30 rounded;
}
</style>
