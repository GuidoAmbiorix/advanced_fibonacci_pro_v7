import sys
import os
import shutil
import multiprocessing
import time
from loguru import logger

# Add backend directory to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app.services.terminal_manager import TerminalManager
from app.services.account_worker import AccountWorker

def test_terminal_cloning():
    logger.info("--- Testing Terminal Cloning ---")
    
    # Create a dummy MT5 folder
    dummy_source = "C:\\Temp\\MockMT5_Source"
    dummy_dest_name = "MockMT5_Clone"
    
    os.makedirs(dummy_source, exist_ok=True)
    with open(os.path.join(dummy_source, "terminal64.exe"), "w") as f:
        f.write("mock exe content")
        
    # Test Cloning
    result = TerminalManager.clone_terminal(dummy_source, dummy_dest_name)
    logger.info(f"Cloning Result: {result}")
    
    if result['success']:
        if os.path.exists(result['path']) and os.path.exists(result['exe_path']):
            logger.success("R Terminal Cloning Verified")
            # Cleanup
            shutil.rmtree(result['path'])
        else:
            logger.error("❌ Clone path invalid")
    else:
        logger.error(f"❌ Cloning Failed: {result.get('error')}")
        
    # Cleanup Source
    shutil.rmtree(dummy_source)

def test_worker_process():
    logger.info("\n--- Testing Account Worker Process ---")
    
    cmd_q = multiprocessing.Queue()
    resp_q = multiprocessing.Queue()
    
    config = {
        "login": "123456",
        "password": "password",
        "server": "Demo-Server",
        "terminal_path": "C:\\Mock\\MT5\\terminal64.exe" # Path won't be used as we mock connection
    }
    
    # We need to mock MT5 in the worker? 
    # The worker imports mt5 globally. We can't easily mock it inside the process without injecting.
    # But checking if the process STARTS is a good first step.
    
    worker = AccountWorker("TestWorker-1", config, cmd_q, resp_q)
    worker.start()
    
    logger.info(f"Worker spawned with PID: {worker.pid}")
    
    # Wait for startup response (it will likely fail connection, but that's a response!)
    try:
        response = resp_q.get(timeout=5)
        logger.info(f"Received from Worker: {response}")
        logger.success("R Worker Communication Verified")
    except Exception as e:
        logger.error(f"❌ Worker timed out: {e}")
        
    # Stop Worker
    cmd_q.put({"type": "STOP"})
    worker.join()
    logger.info("Worker stopped.")

if __name__ == "__main__":
    multiprocessing.freeze_support()
    logger.remove()
    logger.add(sys.stderr, level="INFO")
    
    test_terminal_cloning()
    test_worker_process()
