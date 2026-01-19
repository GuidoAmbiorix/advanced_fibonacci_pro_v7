"""
MT5 GUI Automation Wrapper
Uses subprocess to launch and pyautogui for keyboard control
"""
import time
import os
import subprocess

class MT5GUIWrapper:
    def __init__(self, terminal_path):
        self.terminal_path = terminal_path
        self.process = None

    def launch_and_wait(self, config_path):
        """
        Lanza MT5 con la configuración dada usando subprocess.
        """
        print(f"🖥️ GUI: Launching MT5...")
        
        try:
            # Kill any existing MT5 first
            subprocess.run(["taskkill", "/f", "/im", "terminal64.exe"], 
                          stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
            time.sleep(2)
            
            # Launch MT5 with config
            cmd = f'"{self.terminal_path}" /config:"{config_path}"'
            self.process = subprocess.Popen(cmd, shell=True)
            print("🖥️ GUI: Started MT5 instance.")
            
            # Wait for MT5 to fully load (login, connect, etc)
            print("⏳ Waiting 30s for MT5 to fully load...")
            time.sleep(30)
            
            return True
            
        except Exception as e:
            print(f"❌ GUI Error: {e}")
            return False

    def ensure_strategy_tester_open(self):
        """
        Abre Strategy Tester con Ctrl+R
        """
        print("🖥️ GUI: Opening Strategy Tester (Ctrl+R)...")
        try:
            import pyautogui
            pyautogui.hotkey('ctrl', 'r')
            time.sleep(3)
            print("✅ Strategy Tester should be open now")
        except Exception as e:
            print(f"⚠️ GUI Warning: Could not send Ctrl+R. {e}")

    def start_backtest_and_wait(self, max_minutes=10):
        """
        Click Start button using Tab navigation and Enter
        Since there's no direct shortcut, we use Tab to navigate to Start button
        """
        print("🖥️ GUI: Attempting to start backtest...")
        
        try:
            import pyautogui
            
            # Strategy: Since MT5 has focus on the Tester after Ctrl+R,
            # we can try clicking at a known position or using Tab+Enter
            
            # Method 1: Try clicking the green Start button area
            # The Start button is usually in the bottom-right of the Tester panel
            # We'll use a more reliable method: send Enter key multiple times
            # as the Start button often has focus after opening tester
            
            # First, ensure MT5 is focused by clicking on it
            # Get the MT5 window and bring to front
            try:
                import pygetwindow as gw
                mt5_windows = gw.getWindowsWithTitle('MetaTrader')
                if mt5_windows:
                    mt5_windows[0].activate()
                    time.sleep(1)
            except:
                pass
            
            # Send Ctrl+R to ensure Tester is focused
            pyautogui.hotkey('ctrl', 'r')
            time.sleep(2)
            
            # Try pressing Enter - Start button often has default focus
            pyautogui.press('enter')
            print("✅ GUI: Sent Enter key to start test")
            
            time.sleep(3)
            return True
            
        except ImportError:
            print("❌ pyautogui not installed. Run: pip install pyautogui")
            return False
        except Exception as e:
            print(f"❌ GUI Error: Failed to start backtest. {e}")
            return False

    def close_terminal(self):
        """Cierra el terminal"""
        try:
            if self.process:
                self.process.terminate()
            subprocess.run(["taskkill", "/f", "/im", "terminal64.exe"], 
                          stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
            print("🖥️ GUI: Terminal closed.")
        except:
            pass
