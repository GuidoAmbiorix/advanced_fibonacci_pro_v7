# Implementation Plan - Socket.IO Integration

## Goal
Replace the deprecated raw WebSocket implementation with **Socket.IO** for robust, event-based real-time communication between the backend and frontend.

## User Review Required
> [!IMPORTANT]
> **Dependency Installation**: You will need to install new packages for both backend and frontend.
> - Backend: `pip install python-socketio`
> - Frontend: `npm install socket.io-client`

## Proposed Changes

### [Backend] Main Application
#### [MODIFY] [main.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/main.py)
- Import `socketio`.
- Create `sio = socketio.AsyncServer(async_mode='asgi', cors_allowed_origins=[...])`.
- Wrap FastAPI app: `app = socketio.ASGIApp(sio, app)`.
- Define event handlers: `@sio.event async def connect(sid, environ): ...`

### [Backend] Trading Bot
#### [MODIFY] [trading_bot.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/services/trading_bot.py)
- Inject the global `sio` instance into `TradingBot`.
- Emit events on key actions:
    - `await self.sio.emit('signal_generated', signal_data)`
    - `await self.sio.emit('trade_opened', trade_data)`
    - `await self.sio.emit('trade_closed', trade_data)`

### [Frontend] API Service
#### [MODIFY] [api.js](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/services/api.js)
- Import `io` from `socket.io-client`.
- Replace `createWebSocket` with `initSocket`:
    ```javascript
    initSocket() {
      const socket = io(API_BASE_URL);
      return socket;
    }
    ```

### [Frontend] Dashboard
#### [MODIFY] [ExecutionDashboard.vue](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/components/ExecutionDashboard.vue)
- Use `api.initSocket()` on mount.
- Listen for events:
    - `socket.on('signal_generated', (signal) => { ... })`
    - `socket.on('trade_opened', (trade) => { ... })`

## Verification Plan
1.  **Install Dependencies**: Run pip and npm install commands.
2.  **Start System**: Launch backend and frontend.
3.  **Verify Connection**: Check browser console for "Socket connected".
4.  **Test Events**: Manually trigger a signal or trade and verify it appears instantly on the dashboard without refreshing.
