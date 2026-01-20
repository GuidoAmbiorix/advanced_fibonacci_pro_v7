<template>
  <div class="backtest-logs">
    <div class="logs-header">
      <h3 class="logs-title">
        <i class="icon-terminal"></i> Backtest Logs
        <span v-if="logs.length" class="log-count">({{ logs.length }})</span>
      </h3>
      <div class="logs-controls">
        <select v-model="levelFilter" class="level-filter">
          <option value="ALL">All Levels</option>
          <option value="INFO">INFO</option>
          <option value="WARNING">WARNING</option>
          <option value="ERROR">ERROR</option>
        </select>
        <button @click="toggleAutoScroll" class="btn-icon" :class="{ active: autoScroll }">
          <i class="icon-scroll"></i>
        </button>
        <button @click="clearLogs" class="btn-icon btn-danger">
          <i class="icon-trash"></i>
        </button>
        <button @click="toggleCollapsed" class="btn-icon">
          <i :class="collapsed ? 'icon-expand' : 'icon-collapse'"></i>
        </button>
      </div>
    </div>

    <div v-if="!collapsed" class="logs-container" ref="logsContainer">
      <div v-if="filteredLogs.length === 0" class="logs-empty">
        No logs yet. Run a backtest to see detailed execution logs.
      </div>
      <div
        v-for="(log, idx) in filteredLogs"
        :key="idx"
        class="log-entry"
        :class="'log-' + log.level.toLowerCase()"
      >
        <span class="log-time">{{ formatTime(log.timestamp) }}</span>
        <span class="log-level" :class="'level-' + log.level.toLowerCase()">{{ log.level }}</span>
        <span class="log-message">{{ log.message }}</span>
        <span v-if="log.data && Object.keys(log.data).length" class="log-data" @click="toggleData(idx)">
          <i class="icon-info"></i>
          <div v-if="expandedLogs[idx]" class="log-data-popup">
            <pre>{{ JSON.stringify(log.data, null, 2) }}</pre>
          </div>
        </span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { io } from 'socket.io-client'

const props = defineProps({
  sessionId: {
    type: [Number, String],
    default: null
  }
})

const logs = ref([])
const levelFilter = ref('ALL')
const autoScroll = ref(true)
const collapsed = ref(false)
const expandedLogs = ref({})
const logsContainer = ref(null)

// Socket connection
let socket = null

const filteredLogs = computed(() => {
  if (levelFilter.value === 'ALL') return logs.value
  return logs.value.filter(log => log.level === levelFilter.value)
})

const formatTime = (timestamp) => {
  if (!timestamp) return ''
  const date = new Date(timestamp)
  return date.toLocaleTimeString('en-US', { hour12: false })
}

const toggleData = (idx) => {
  expandedLogs.value[idx] = !expandedLogs.value[idx]
}

const toggleAutoScroll = () => {
  autoScroll.value = !autoScroll.value
}

const toggleCollapsed = () => {
  collapsed.value = !collapsed.value
}

const clearLogs = () => {
  logs.value = []
  expandedLogs.value = {}
}

const scrollToBottom = () => {
  if (autoScroll.value && logsContainer.value) {
    nextTick(() => {
      logsContainer.value.scrollTop = logsContainer.value.scrollHeight
    })
  }
}

// Watch for new logs and scroll
watch(logs, () => {
  scrollToBottom()
}, { deep: true })

// Setup socket listener
onMounted(() => {
  const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:8000'
  socket = io(apiUrl, { transports: ['websocket'] })

  socket.on('backtest_log', (data) => {
    // Filter by session if sessionId is provided
    if (props.sessionId && data.session_id && data.session_id !== props.sessionId) {
      return
    }
    logs.value.push(data)
    // Limit to last 500 logs
    if (logs.value.length > 500) {
      logs.value = logs.value.slice(-500)
    }
  })
})

onUnmounted(() => {
  if (socket) {
    socket.off('backtest_log')
    socket.disconnect()
  }
})

// Expose methods for parent components
defineExpose({
  clearLogs,
  logs
})
</script>

<style scoped>
.backtest-logs {
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 12px;
  margin-top: 1.5rem;
  overflow: hidden;
}

.logs-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.75rem 1rem;
  background: rgba(30, 41, 59, 0.8);
  border-bottom: 1px solid rgba(59, 130, 246, 0.2);
}

.logs-title {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.9rem;
  font-weight: 600;
  color: #e2e8f0;
  margin: 0;
}

.log-count {
  color: #64748b;
  font-weight: 400;
}

.logs-controls {
  display: flex;
  gap: 0.5rem;
  align-items: center;
}

.level-filter {
  background: rgba(15, 23, 42, 0.8);
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 6px;
  color: #e2e8f0;
  padding: 0.25rem 0.5rem;
  font-size: 0.75rem;
}

.btn-icon {
  background: rgba(59, 130, 246, 0.2);
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 6px;
  color: #94a3b8;
  padding: 0.25rem 0.5rem;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-icon:hover {
  background: rgba(59, 130, 246, 0.3);
  color: #e2e8f0;
}

.btn-icon.active {
  background: rgba(59, 130, 246, 0.5);
  color: #fff;
}

.btn-icon.btn-danger:hover {
  background: rgba(239, 68, 68, 0.3);
  border-color: rgba(239, 68, 68, 0.5);
}

.logs-container {
  max-height: 300px;
  overflow-y: auto;
  padding: 0.5rem;
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
  font-size: 0.75rem;
}

.logs-empty {
  text-align: center;
  color: #64748b;
  padding: 2rem;
}

.log-entry {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  margin-bottom: 2px;
  line-height: 1.4;
}

.log-entry:hover {
  background: rgba(59, 130, 246, 0.1);
}

.log-time {
  color: #64748b;
  flex-shrink: 0;
}

.log-level {
  font-weight: 600;
  padding: 0 0.25rem;
  border-radius: 3px;
  flex-shrink: 0;
  min-width: 50px;
  text-align: center;
}

.level-info {
  background: rgba(59, 130, 246, 0.2);
  color: #60a5fa;
}

.level-warning {
  background: rgba(234, 179, 8, 0.2);
  color: #facc15;
}

.level-error {
  background: rgba(239, 68, 68, 0.2);
  color: #f87171;
}

.log-message {
  color: #e2e8f0;
  flex: 1;
  word-break: break-word;
}

.log-info .log-message {
  color: #cbd5e1;
}

.log-warning .log-message {
  color: #fef08a;
}

.log-error .log-message {
  color: #fca5a5;
}

.log-data {
  position: relative;
  cursor: pointer;
  color: #64748b;
}

.log-data:hover {
  color: #94a3b8;
}

.log-data-popup {
  position: absolute;
  right: 0;
  top: 100%;
  background: #1e293b;
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 8px;
  padding: 0.5rem;
  z-index: 100;
  max-width: 400px;
  max-height: 200px;
  overflow: auto;
}

.log-data-popup pre {
  margin: 0;
  font-size: 0.7rem;
  color: #94a3b8;
}

/* Icons (simple unicode fallbacks) */
.icon-terminal::before { content: '⌨'; }
.icon-scroll::before { content: '↓'; }
.icon-trash::before { content: '🗑'; }
.icon-expand::before { content: '▼'; }
.icon-collapse::before { content: '▲'; }
.icon-info::before { content: 'ℹ'; }
</style>
