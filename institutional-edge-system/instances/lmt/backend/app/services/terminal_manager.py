import os
import shutil
import glob
from typing import List, Dict, Optional
from loguru import logger
import winreg

class TerminalManager:
    """
    Manages MetaTrader 5 Terminal installations (folders).
    Allows cloning existing terminals to create isolated environments for multi-account trading.
    """

    DEFAULT_BASE_PATHS = [
        r"C:\Program Files\MetaTrader 5",
        r"C:\Program Files (x86)\MetaTrader 5",
        r"C:\MetaTrader 5"
    ]

    @staticmethod
    def clone_terminal(source_path: str, new_name: str) -> Dict:
        """
        Clones an existing MT5 terminal folder to a new location.
        Cleaning up non-essential files (logs, history) is recommended but minimal copy is safer.
        
        Args:
            source_path: Path to the base terminal (e.g., C:/Program Files/MetaTrader 5)
            new_name: Name for the new instance (e.g., "PropFirm_1")
            
        Returns:
            Dict containing 'success', 'path', or 'error'
        """
        try:
            if not os.path.exists(source_path):
                return {"success": False, "error": f"Source path does not exist: {source_path}"}
            
            # Construct new path
            # DEFAULT TO A USER WRITABLE DIRECTORY TO AVOID PERMISSION ERRORS (Program Files is restricted)
            user_documents = os.path.join(os.path.expanduser("~"), "Documents")
            instances_dir = os.path.join(user_documents, "MT5_Instances")
            
            if not os.path.exists(instances_dir):
                os.makedirs(instances_dir)
                
            destination_path = os.path.join(instances_dir, f"MetaTrader 5 {new_name}")
            
            # Legacy fallback: if we really wanted to clone in place (requires optimized permissions), we would use:
            # parent_dir = os.path.dirname(source_path.rstrip(os.sep))
            
            if os.path.exists(destination_path):
                return {"success": False, "error": f"Destination already exists: {destination_path}"}
            
            logger.info(f"Cloning terminal from '{source_path}' to '{destination_path}'...")
            
            # Copy the entire directory tree
            # shutil.copytree is robust for this. dirs_exist_ok=False prevents overwriting.
            shutil.copytree(source_path, destination_path)
            
            # Optional: Clean up specific subdirectories in the NEW copy to make it "fresh"
            # We don't want old logs or MQL5 compiled cache possibly
            dirs_to_clean = ["Logs", "bases", "crashes"] # Be careful deleting 'bases' if it has history
            
            for d in dirs_to_clean:
               full_p = os.path.join(destination_path, d)
               if os.path.exists(full_p):
                   try:
                       shutil.rmtree(full_p)
                       os.makedirs(full_p) # Recreate empty
                   except Exception as e:
                       logger.warning(f"Could not clean {d} in new terminal: {e}")

            logger.info("Terminal cloned successfully.")
            
            return {
                "success": True, 
                "path": destination_path,
                "exe_path": os.path.join(destination_path, "terminal64.exe")
            }

        except Exception as e:
            logger.exception("Failed to clone terminal")
            return {"success": False, "error": str(e)}

    @staticmethod
    def detect_terminals() -> List[Dict]:
        """
        Scans common directories to find valid MT5 installations.
        Checks for presence of 'terminal64.exe'.
        """
        found_terminals = []
        
        # 1. Check known default paths
        search_roots = TerminalManager.DEFAULT_BASE_PATHS
        
        # 2. Add 'Program Files' scan for any folder starting with "MetaTrader"
        try:
            prog_files = os.environ.get("ProgramFiles", r"C:\Program Files")
            for d in os.listdir(prog_files):
                if d.lower().startswith("metatrader"):
                    full_p = os.path.join(prog_files, d)
                    if full_p not in search_roots:
                        search_roots.append(full_p)
        except Exception:
            pass

        # 3. Add User Documents MT5_Instances
        try:
            user_documents = os.path.join(os.path.expanduser("~"), "Documents")
            instances_dir = os.path.join(user_documents, "MT5_Instances")
            if os.path.exists(instances_dir):
                for d in os.listdir(instances_dir):
                     full_p = os.path.join(instances_dir, d)
                     if full_p not in search_roots:
                        search_roots.append(full_p)
        except Exception:
            pass
            
        # 4. Validate and collect
        for root in search_roots:
            if os.path.exists(root):
                exe_path = os.path.join(root, "terminal64.exe")
                if os.path.exists(exe_path):
                    found_terminals.append({
                        "name": os.path.basename(root),
                        "path": root,
                        "exe_path": exe_path
                    })
        
        return found_terminals

    @staticmethod
    def validate_terminal_path(path: str) -> bool:
        """Verifies if a path points to a valid MT5 terminal folder."""
        if not path or not os.path.exists(path):
            return False
            
        exe_path = os.path.join(path, "terminal64.exe")
        return os.path.exists(exe_path)
