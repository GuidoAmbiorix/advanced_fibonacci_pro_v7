<template>
  <div class="drawing-toolbar">
    <!-- Tool Selection -->
    <div class="tool-group">
      <button
        v-for="tool in drawingTools"
        :key="tool.id"
        @click="selectTool(tool.id)"
        :class="['tool-btn', { active: activeTool === tool.id }]"
        :title="tool.label"
      >
        <component :is="tool.icon" class="w-5 h-5" />
      </button>
    </div>

    <!-- Separator -->
    <div class="divider"></div>

    <!-- Zone Actions -->
    <div class="action-group">
      <select v-model="zoneAction" class="zone-action-select">
        <option value="NEUTRAL">Informational</option>
        <option value="BUY_ONLY">Buy Zone Only</option>
        <option value="SELL_ONLY">Sell Zone Only</option>
        <option value="NO_TRADE">No Trade Zone</option>
      </select>

      <input
        v-model="zoneColor"
        type="color"
        class="color-picker"
        title="Zone Color"
      />
    </div>

    <!-- Separator -->
    <div class="divider"></div>

    <!-- Template Management -->
    <div class="template-group">
      <button @click="$emit('saveTemplate')" class="template-btn" title="Save as Template">
        <BookmarkIcon class="w-5 h-5" />
      </button>
      <button @click="showTemplates = true" class="template-btn" title="Load Template">
        <FolderOpenIcon class="w-5 h-5" />
      </button>
      <button @click="clearAll" class="template-btn text-red-500" title="Clear All">
        <TrashIcon class="w-5 h-5" />
      </button>
    </div>

    <!-- Template Library Modal -->
    <TemplateLibraryModal
      v-if="showTemplates"
      :templates="templates"
      @load="loadTemplate"
      @delete="deleteTemplate"
      @close="showTemplates = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import {
  MinusIcon,
  ArrowTrendingUpIcon,
  ChartBarIcon,
  BookmarkIcon,
  FolderOpenIcon,
  TrashIcon
} from '@heroicons/vue/24/outline'
import TemplateLibraryModal from './TemplateLibraryModal.vue'

interface DrawingTool {
  id: 'horizontal_zone' | 'trend_line' | 'fibonacci' | 'order_block'
  label: string
  icon: any
}

const drawingTools: DrawingTool[] = [
  { id: 'horizontal_zone', label: 'Horizontal Zone', icon: MinusIcon },
  { id: 'trend_line', label: 'Trend Line', icon: ArrowTrendingUpIcon },
  { id: 'fibonacci', label: 'Fibonacci', icon: ChartBarIcon },
  { id: 'order_block', label: 'Order Block', icon: ChartBarIcon }
]

const activeTool = ref<string | null>(null)
const zoneAction = ref<'NEUTRAL' | 'BUY_ONLY' | 'SELL_ONLY' | 'NO_TRADE'>('NEUTRAL')
const zoneColor = ref('#3B82F6')
const showTemplates = ref(false)
const templates = ref<any[]>([])

const emit = defineEmits(['toolSelected', 'saveTemplate', 'loadTemplate', 'clearAll'])

function selectTool(toolId: string) {
  activeTool.value = activeTool.value === toolId ? null : toolId
  emit('toolSelected', {
    tool: toolId,
    action: zoneAction.value,
    color: zoneColor.value
  })
}

function loadTemplate(template: any) {
  emit('loadTemplate', template)
  showTemplates.value = false
}

function deleteTemplate(templateId: number) {
  // Emit to parent for API call
  emit('deleteTemplate', templateId)
}

function clearAll() {
  if (confirm('Clear all annotations from this chart?')) {
    emit('clearAll')
  }
}
</script>

<style scoped>
.drawing-toolbar {
  @apply flex items-center gap-2 bg-gray-800 p-2 rounded-lg border border-gray-700;
}

.tool-group, .action-group, .template-group {
  @apply flex items-center gap-1;
}

.tool-btn {
  @apply p-2 rounded hover:bg-gray-700 transition-colors text-gray-300;
}

.tool-btn.active {
  @apply bg-blue-600 text-white;
}

.divider {
  @apply h-6 w-px bg-gray-600;
}

.zone-action-select {
  @apply bg-gray-700 text-white text-sm px-2 py-1 rounded border border-gray-600;
}

.color-picker {
  @apply w-8 h-8 rounded cursor-pointer border border-gray-600;
}

.template-btn {
  @apply p-2 rounded hover:bg-gray-700 transition-colors text-gray-300;
}
</style>
