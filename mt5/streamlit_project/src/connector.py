import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime
import streamlit as st

class MT5Connector:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(MT5Connector, cls).__new__(cls)
            cls._instance.initialized = False
        return cls._instance

    def connect(self) -> bool:
        """Initializes the connection to the MT5 terminal."""
        if not self.initialized:
            if not mt5.initialize():
                st.error(f"MT5 Initialization failed, error code: {mt5.last_error()}")
                return False
            self.initialized = True
        return True

    def disconnect(self):
        """Shuts down the MT5 connection."""
        if self.initialized:
            mt5.shutdown()
            self.initialized = False

    def get_account_info(self):
        """Returns account information as a dictionary."""
        if not self.connect():
            return None
        
        info = mt5.account_info()
        if info:
            return info._asdict()
        return None

    def get_terminal_info(self):
        """Returns terminal information."""
        if not self.connect():
            return None
        
        info = mt5.terminal_info()
        if info:
            return info._asdict()
        return None
