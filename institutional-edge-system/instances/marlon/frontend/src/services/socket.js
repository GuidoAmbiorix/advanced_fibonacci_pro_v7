/**
 * ============================================================================
 * Socket.IO Client - Enhanced with Reconnection & Heartbeat
 * ============================================================================
 * Features:
 * - Automatic reconnection with exponential backoff
 * - Heartbeat ping/pong for connection health
 * - Connection state tracking
 * - Debug logging
 */

import { io } from "socket.io-client";
import { ref, readonly } from "vue";

// Configuration
const SOCKET_URL = import.meta.env.VITE_API_BASE_URL || "";
const MAX_RECONNECT_ATTEMPTS = 10;
const RECONNECT_DELAY_BASE = 1000; // 1 second base delay
const HEARTBEAT_INTERVAL = 30000; // 30 seconds

// Reactive state
const isConnected = ref(false);
const isReconnecting = ref(false);
const reconnectAttempts = ref(0);
const lastHeartbeat = ref(null);

// Create socket with enhanced options
const socket = io(SOCKET_URL, {
  autoConnect: false,
  transports: ["websocket", "polling"], // Fallback to polling if websocket fails
  reconnection: true,
  reconnectionAttempts: MAX_RECONNECT_ATTEMPTS,
  reconnectionDelay: RECONNECT_DELAY_BASE,
  reconnectionDelayMax: 10000, // Max 10 seconds between attempts
  timeout: 20000, // 20 second connection timeout
});

// Heartbeat timer
let heartbeatTimer = null;

// ==================== Connection Event Handlers ====================

socket.on("connect", () => {
  console.log("🟢 Socket connected:", socket.id);
  isConnected.value = true;
  isReconnecting.value = false;
  reconnectAttempts.value = 0;

  // Start heartbeat
  startHeartbeat();
});

socket.on("disconnect", (reason) => {
  console.log("🔴 Socket disconnected:", reason);
  isConnected.value = false;

  // Stop heartbeat
  stopHeartbeat();

  // If not a manual disconnect, try to reconnect
  if (reason === "io server disconnect") {
    // Server initiated disconnect, manually reconnect
    socket.connect();
  }
});

socket.on("connect_error", (error) => {
  console.error("⚠️ Socket connection error:", error.message);
  isConnected.value = false;
});

socket.io.on("reconnect_attempt", (attempt) => {
  console.log(`🔄 Reconnection attempt ${attempt}/${MAX_RECONNECT_ATTEMPTS}`);
  isReconnecting.value = true;
  reconnectAttempts.value = attempt;
});

socket.io.on("reconnect", (attempt) => {
  console.log(`✅ Reconnected after ${attempt} attempts`);
  isConnected.value = true;
  isReconnecting.value = false;
  reconnectAttempts.value = 0;
});

socket.io.on("reconnect_failed", () => {
  console.error("❌ Reconnection failed after max attempts");
  isReconnecting.value = false;
});

// ==================== Heartbeat ====================

socket.on("pong", () => {
  lastHeartbeat.value = new Date();
  console.debug("💓 Heartbeat received");
});

function startHeartbeat() {
  stopHeartbeat(); // Clear any existing timer

  heartbeatTimer = setInterval(() => {
    if (socket.connected) {
      socket.emit("ping");
      console.debug("💗 Heartbeat sent");
    }
  }, HEARTBEAT_INTERVAL);
}

function stopHeartbeat() {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }
}

// ==================== Debug Logging ====================

if (import.meta.env.DEV) {
  socket.onAny((event, ...args) => {
    // Skip noisy events
    if (event === "pong" || event === "market_update") return;
    console.log(`📨 [${event}]`, args);
  });
}

// ==================== Manual Connection Control ====================

export function connectSocket() {
  if (!socket.connected) {
    console.log("🔌 Connecting socket...");
    socket.connect();
  }
}

export function disconnectSocket() {
  console.log("🔌 Disconnecting socket...");
  stopHeartbeat();
  socket.disconnect();
}

export function forceReconnect() {
  console.log("🔄 Force reconnecting...");
  socket.disconnect();
  setTimeout(() => socket.connect(), 500);
}

// ==================== Exports ====================

export const connectionState = {
  isConnected: readonly(isConnected),
  isReconnecting: readonly(isReconnecting),
  reconnectAttempts: readonly(reconnectAttempts),
  lastHeartbeat: readonly(lastHeartbeat),
};

export default socket;
