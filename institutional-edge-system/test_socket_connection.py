
import asyncio
import socketio

sio = socketio.AsyncClient()

@sio.event
async def connect():
    print("Test connection established")

@sio.event
async def connect_error(data):
    print("The connection failed!", data)

@sio.event
async def disconnect():
    print("Disconnected from server")

async def main():
    try:
        # Try to connect to localhost:8000
        # standard fallback is polling then websocket
        print("Attempting to connect to http://localhost:8000")
        await sio.connect('http://localhost:8000', socketio_path='socket.io')
        print("Connected via", sio.transport)
        await sio.wait()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    asyncio.run(main())
