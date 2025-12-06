import { io } from "socket.io-client";

const URL = "http://localhost:8000"; // Adjust if needed
const socket = io(URL, {
  autoConnect: false,
  transports: ["websocket"]
});

socket.onAny((event, ...args) => {
  console.log(event, args);
});

export default socket;
