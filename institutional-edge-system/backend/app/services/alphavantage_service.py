import httpx
from typing import Dict, Optional
from loguru import logger
from app.core.config import settings

class AlphaVantageService:
    """
    Service to interact with AlphaVantage API for fundamental data.
    """
    BASE_URL = "https://www.alphavantage.co/query"

    def __init__(self):
        self.api_key = settings.ALPHAVANTAGE_API_KEY
        if not self.api_key:
            logger.warning("AlphaVantage API Key is missing. Fundamental data will not be available.")

    async def get_company_overview(self, symbol: str) -> Optional[Dict]:
        """
        Get company overview (PE, EPS, Sector, etc.)
        """
        if not self.api_key:
            return None

        # Clean symbol (remove # for crypto if present, though fundamentals are mostly for stocks)
        clean_symbol = symbol.replace("#", "")

        params = {
            "function": "OVERVIEW",
            "symbol": clean_symbol,
            "apikey": self.api_key
        }

        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(self.BASE_URL, params=params)
                data = response.json()

                if "Note" in data:
                    logger.warning(f"AlphaVantage API limit reached: {data['Note']}")
                    return None
                
                if not data or "Symbol" not in data:
                    logger.warning(f"No fundamental data found for {symbol}")
                    return None

                return {
                    "Symbol": data.get("Symbol"),
                    "Sector": data.get("Sector"),
                    "Industry": data.get("Industry"),
                    "PE_Ratio": data.get("PERatio"),
                    "EPS": data.get("EPS"),
                    "DividendYield": data.get("DividendYield"),
                    "52WeekHigh": data.get("52WeekHigh"),
                    "52WeekLow": data.get("52WeekLow"),
                    "Description": data.get("Description")
                }

        except Exception as e:
            logger.error(f"Error fetching AlphaVantage data for {symbol}: {e}")
            return None

    async def get_sentiment(self, symbol: str) -> Optional[Dict]:
        """
        Get market sentiment for a symbol
        """
        if not self.api_key:
            return None
            
        clean_symbol = symbol.replace("#", "")

        params = {
            "function": "NEWS_SENTIMENT",
            "tickers": clean_symbol,
            "limit": 1, # Just get the latest to gauge general sentiment
            "apikey": self.api_key
        }

        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(self.BASE_URL, params=params)
                data = response.json()

                if "feed" not in data:
                    return None
                
                # Calculate average sentiment from recent news
                sentiment_scores = []
                for item in data.get("feed", []):
                    for ticker_sentiment in item.get("ticker_sentiment", []):
                        if ticker_sentiment["ticker"] == clean_symbol:
                            sentiment_scores.append(float(ticker_sentiment["ticker_sentiment_score"]))
                
                if not sentiment_scores:
                    return {"sentiment_score": 0, "sentiment_label": "Neutral"}

                avg_score = sum(sentiment_scores) / len(sentiment_scores)
                
                label = "Neutral"
                if avg_score > 0.15: label = "Bullish"
                if avg_score > 0.35: label = "Strong Bullish"
                if avg_score < -0.15: label = "Bearish"
                if avg_score < -0.35: label = "Strong Bearish"

                return {
                    "sentiment_score": avg_score,
                    "sentiment_label": label
                }

        except Exception as e:
            logger.error(f"Error fetching sentiment for {symbol}: {e}")
            return None

# Global instance
alphavantage_service = AlphaVantageService()
