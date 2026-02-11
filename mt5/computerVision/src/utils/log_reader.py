
import os
import shutil
from typing import List, Optional, Generator
import docker
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class LogReader:
    """
    Utility to read logs from files or Docker containers efficiently.
    """
    
    @staticmethod
    def read_file_tail(file_path: str, n_lines: int = 100) -> List[str]:
        """
        Reads the last n lines of a file without loading the whole file into memory.
        Efficient for large log files.
        """
        if not os.path.exists(file_path):
            return [f"File not found: {file_path}"]
            
        try:
            # Use 'tail' command on Linux if available for speed, but pure python callback for cross-platform/container
            # Python 'seek' method for large files
            
            with open(file_path, 'rb') as f:
                # Go to end
                f.seek(0, 2)
                file_size = f.tell()
                
                # If file is small, just read it
                if file_size < 10000: 
                    f.seek(0)
                    return f.read().decode('utf-8', errors='ignore').splitlines()
                
                # Backtrack to find last n lines
                block_size = 1024
                data = b''
                lines_found = 0
                
                # Start reading from end backwards
                pos = file_size
                
                while pos > 0 and lines_found < n_lines + 1:
                    read_len = min(block_size, pos)
                    pos -= read_len
                    f.seek(pos)
                    chunk = f.read(read_len)
                    data = chunk + data
                    lines_found = data.count(b'\n')
                
                # Decode and split
                text = data.decode('utf-8', errors='ignore')
                lines = text.splitlines()
                return lines[-n_lines:]
                
        except Exception as e:
            return [f"Error reading file: {e}"]

class DockerLogManager:
    """
    Manages connection to Docker daemon to stream logs.
    """
    
    def __init__(self):
        try:
            self.client = docker.from_env()
            self.connected = True
        except Exception as e:
            logger.warning(f"Could not connect to Docker: {e}")
            self.client = None
            self.connected = False
            self.error = str(e)

    def list_containers(self) -> List[dict]:
        if not self.connected:
            return []
        try:
            containers = self.client.containers.list(all=True)
            return [{'name': c.name, 'status': c.status, 'id': c.short_id} for c in containers]
        except Exception as e:
            logger.error(f"Error listing containers: {e}")
            return []
            
    def get_logs(self, container_name: str, tail: int = 100) -> str:
        if not self.connected:
            return f"Docker not connected: {self.error}"
            
        try:
            container = self.client.containers.get(container_name)
            # logs returns bytes
            logs = container.logs(tail=tail, timestamps=True)
            return logs.decode('utf-8', errors='ignore')
        except docker.errors.NotFound:
            return f"Container '{container_name}' not found."
        except Exception as e:
            return f"Error fetching logs: {e}"
