
import os
import time
from src.utils.log_reader import LogReader, DockerLogManager

def test_file_reader():
    print("Testing FileLogReader...")
    filename = "test_log.txt"
    with open(filename, "w") as f:
        for i in range(1000):
            f.write(f"Line {i}\n")
    
    try:
        lines = LogReader.read_file_tail(filename, 10)
        print(f"Read {len(lines)} lines.")
        print(f"Last line: {lines[-1]}")
        assert len(lines) == 10
        assert "Line 999" in lines[-1]
        print("✅ FileLogReader OK")
    except Exception as e:
        print(f"❌ FileLogReader Failed: {e}")
    finally:
        if os.path.exists(filename):
            os.remove(filename)

def test_docker_reader():
    print("\nTesting DockerLogManager...")
    mgr = DockerLogManager()
    if mgr.connected:
        print("✅ Docker connected")
        containers = mgr.list_containers()
        print(f"Found {len(containers)} containers")
        if containers:
            logs = mgr.get_logs(containers[0]['name'], tail=5)
            print("Successfully fetched logs sample.")
        else:
            print("⚠️ No containers to test logs.")
    else:
        print(f"⚠️ Docker not connected (Expected if no socket): {mgr.error}")

if __name__ == "__main__":
    test_file_reader()
    test_docker_reader()
