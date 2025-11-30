
import unittest
import asyncio
from unittest.mock import patch, MagicMock
from app.services.telegram_service import TelegramService

class TestTelegramIntegration(unittest.TestCase):
    def setUp(self):
        self.bot_token = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
        self.chat_id = "123456789"
        self.service = TelegramService(self.bot_token, self.chat_id)

    @patch('aiohttp.ClientSession.post')
    def test_send_message_success(self, mock_post):
        """Test successful message sending"""
        # Mock response context manager
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__aenter__.return_value = mock_response
        mock_response.__aexit__.return_value = None
        
        # Mock session context manager
        mock_session = MagicMock()
        mock_session.post.return_value = mock_response
        mock_session.__aenter__.return_value = mock_session
        mock_session.__aexit__.return_value = None
        
        # We need to mock ClientSession() to return our mock_session
        with patch('aiohttp.ClientSession', return_value=mock_session):
            loop = asyncio.get_event_loop()
            result = loop.run_until_complete(self.service.send_message("Test Message"))
            self.assertTrue(result)

    @patch('aiohttp.ClientSession.post')
    def test_send_trade_notification(self, mock_post):
        """Test trade notification formatting and sending"""
        # Mock response
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.__aenter__.return_value = mock_response
        mock_response.__aexit__.return_value = None
        
        mock_session = MagicMock()
        mock_session.post.return_value = mock_response
        mock_session.__aenter__.return_value = mock_session
        mock_session.__aexit__.return_value = None
        
        trade_data = {
            'symbol': 'EURUSD',
            'type': 'BUY',
            'entry_price': 1.1050,
            'stop_loss': 1.1000,
            'take_profit': 1.1150,
            'volume': 0.1,
            'confluence_score': 8,
            'time': '2023-10-27 10:00:00 UTC'
        }
        
        with patch('aiohttp.ClientSession', return_value=mock_session):
            loop = asyncio.get_event_loop()
            # We just want to ensure it runs without error and returns True (simulated success)
            # The actual formatting is internal to the method
            result = loop.run_until_complete(self.service.send_trade_notification(trade_data))
            self.assertTrue(result)

if __name__ == '__main__':
    unittest.main()
