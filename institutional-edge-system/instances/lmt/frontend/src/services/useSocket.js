/**
 * ============================================================================
 * useSocket Composable - Vue 3 Socket.IO Integration
 * ============================================================================
 * Provides reactive socket connection management for Vue components
 */

import { ref, onMounted, onUnmounted, readonly } from "vue";
import socket, { connectionState, connectSocket, disconnectSocket } from "./socket";

/**
 * Composable for socket connection management in Vue components
 * @param {Object} options - Configuration options
 * @param {boolean} options.autoConnect - Auto-connect on mount (default: true)
 * @param {boolean} options.autoDisconnect - Auto-disconnect on unmount (default: false)
 */
export function useSocket(options = {}) {
    const { autoConnect = true, autoDisconnect = false } = options;

    // Local event handlers registry
    const handlers = new Map();

    onMounted(() => {
        if (autoConnect) {
            connectSocket();
        }
    });

    onUnmounted(() => {
        // Remove all registered handlers
        handlers.forEach((handler, event) => {
            socket.off(event, handler);
        });
        handlers.clear();

        if (autoDisconnect) {
            disconnectSocket();
        }
    });

    /**
     * Subscribe to a socket event
     * @param {string} event - Event name
     * @param {Function} handler - Event handler
     */
    function on(event, handler) {
        socket.on(event, handler);
        handlers.set(event, handler);
    }

    /**
     * Unsubscribe from a socket event
     * @param {string} event - Event name
     */
    function off(event) {
        const handler = handlers.get(event);
        if (handler) {
            socket.off(event, handler);
            handlers.delete(event);
        }
    }

    /**
     * Emit an event to the server
     * @param {string} event - Event name
     * @param {any} data - Event data
     */
    function emit(event, data) {
        if (socket.connected) {
            socket.emit(event, data);
        } else {
            console.warn(`Cannot emit '${event}' - socket not connected`);
        }
    }

    return {
        // Connection state
        isConnected: connectionState.isConnected,
        isReconnecting: connectionState.isReconnecting,
        reconnectAttempts: connectionState.reconnectAttempts,
        lastHeartbeat: connectionState.lastHeartbeat,

        // Methods
        on,
        off,
        emit,
        connect: connectSocket,
        disconnect: disconnectSocket,

        // Raw socket access (for advanced usage)
        socket: readonly(ref(socket)),
    };
}

export default useSocket;
