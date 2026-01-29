"""
V3 Trading System - FinBERT Sentiment Analysis Service
Analyzes financial news sentiment using pre-trained FinBERT model
"""

import asyncio
import json
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import feedparser
import redis.asyncio as redis
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import torch
import torch.nn.functional as F
import structlog
import os

# Configure logging
log = structlog.get_logger()

# ==================== Configuration ====================

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
MODEL_NAME = os.getenv("MODEL_NAME", "ProsusAI/finbert")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", 8))

# News RSS Feeds
RSS_FEEDS = [
    {
        "name": "ForexFactory",
        "url": "https://www.forexfactory.com/feed/news",
        "symbols": ["EURUSD", "GBPUSD", "USDJPY", "USDCAD", "XAUUSD"]
    },
    {
        "name": "Investing.com Forex",
        "url": "https://www.investing.com/rss/news_285.rss",
        "symbols": ["EURUSD", "GBPUSD", "USDJPY", "USDCAD", "XAUUSD"]
    },
    {
        "name": "Reuters Forex",
        "url": "https://www.reutersagency.com/feed/?taxonomy=best-topics&post_type=best",
        "symbols": ["EURUSD", "GBPUSD", "USDJPY", "USDCAD", "XAUUSD"]
    }
]

# Symbol keyword mappings
SYMBOL_KEYWORDS = {
    "EURUSD": ["euro", "eur", "dollar", "usd", "ecb", "federal reserve", "fed"],
    "GBPUSD": ["pound", "sterling", "gbp", "dollar", "usd", "bank of england", "boe"],
    "USDJPY": ["dollar", "usd", "yen", "jpy", "boj", "bank of japan"],
    "USDCAD": ["dollar", "usd", "canadian dollar", "cad", "oil", "bank of canada"],
    "XAUUSD": ["gold", "xau", "precious metals", "safe haven"]
}

# ==================== FinBERT Analyzer ====================

class FinBERTAnalyzer:
    """FinBERT sentiment analysis engine"""

    def __init__(self):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        log.info("finbert_init", device=str(self.device))

        # Load model and tokenizer
        self.tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
        self.model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME)
        self.model.to(self.device)
        self.model.eval()

        log.info("finbert_loaded", model=MODEL_NAME)

    def analyze_text(self, text: str) -> Dict[str, float]:
        """
        Analyze sentiment of financial text
        Returns: {positive, negative, neutral, composite, confidence}
        """
        # Tokenize
        inputs = self.tokenizer(
            text,
            return_tensors="pt",
            truncation=True,
            max_length=512,
            padding=True
        ).to(self.device)

        # Inference
        with torch.no_grad():
            outputs = self.model(**inputs)
            logits = outputs.logits
            probs = F.softmax(logits, dim=1)[0].cpu().numpy()

        # FinBERT outputs: [negative, neutral, positive]
        negative = float(probs[0])
        neutral = float(probs[1])
        positive = float(probs[2])

        # Composite score: positive - negative
        composite = positive - negative

        # Confidence: max probability
        confidence = float(max(probs))

        return {
            "positive": positive,
            "negative": negative,
            "neutral": neutral,
            "composite": composite,
            "confidence": confidence
        }

    def analyze_batch(self, texts: List[str]) -> List[Dict[str, float]]:
        """Batch analysis for efficiency"""
        results = []
        for text in texts:
            results.append(self.analyze_text(text))
        return results

# ==================== News Fetcher ====================

class NewsFetcher:
    """Fetch and parse RSS news feeds"""

    async def fetch_feed(self, feed_config: Dict) -> List[Dict]:
        """Fetch single RSS feed"""
        try:
            feed = feedparser.parse(feed_config["url"])
            articles = []

            for entry in feed.entries[:50]:  # Last 50 articles
                article = {
                    "headline": entry.get("title", ""),
                    "summary": entry.get("summary", ""),
                    "link": entry.get("link", ""),
                    "published": entry.get("published", ""),
                    "source": feed_config["name"],
                    "symbols": feed_config["symbols"]
                }
                articles.append(article)

            log.info("feed_fetched", source=feed_config["name"], count=len(articles))
            return articles

        except Exception as e:
            log.error("feed_fetch_failed", source=feed_config["name"], error=str(e))
            return []

    async def fetch_all_feeds(self) -> List[Dict]:
        """Fetch all configured RSS feeds"""
        all_articles = []
        for feed_config in RSS_FEEDS:
            articles = await self.fetch_feed(feed_config)
            all_articles.extend(articles)

        return all_articles

    def filter_by_symbol(self, articles: List[Dict], symbol: str) -> List[Dict]:
        """Filter articles relevant to specific symbol"""
        keywords = SYMBOL_KEYWORDS.get(symbol, [])
        filtered = []

        for article in articles:
            text = (article["headline"] + " " + article["summary"]).lower()

            # Check if any keyword appears
            if any(keyword.lower() in text for keyword in keywords):
                filtered.append(article)

        return filtered

# ==================== Sentiment Service ====================

class SentimentService:
    """Main sentiment analysis service"""

    def __init__(self):
        self.analyzer = FinBERTAnalyzer()
        self.news_fetcher = NewsFetcher()
        self.redis_client: Optional[redis.Redis] = None

    async def connect_redis(self):
        """Connect to Redis"""
        self.redis_client = await redis.from_url(
            f"redis://{REDIS_HOST}:{REDIS_PORT}",
            encoding="utf-8",
            decode_responses=True
        )
        await self.redis_client.ping()
        log.info("redis_connected", host=REDIS_HOST, port=REDIS_PORT)

    async def get_symbol_sentiment(self, symbol: str) -> Dict:
        """
        Get aggregated sentiment for a symbol
        Returns rolling 4-hour weighted average
        """
        # Fetch recent news
        all_articles = await self.news_fetcher.fetch_all_feeds()
        symbol_articles = self.news_fetcher.filter_by_symbol(all_articles, symbol)

        if not symbol_articles:
            log.warning("no_articles_found", symbol=symbol)
            return {
                "symbol": symbol,
                "positive": 0.5,
                "negative": 0.3,
                "neutral": 0.2,
                "composite": 0.2,
                "confidence": 0.0,
                "timestamp": datetime.utcnow().isoformat()
            }

        # Analyze sentiment of recent articles
        sentiments = []
        for article in symbol_articles[:20]:  # Analyze last 20 relevant articles
            text = article["headline"] + ". " + article["summary"]
            sentiment = self.analyzer.analyze_text(text)
            sentiments.append(sentiment)

        # Calculate weighted average (recent articles weighted more)
        weights = [1.0 / (i + 1) for i in range(len(sentiments))]  # Exponential decay
        total_weight = sum(weights)

        avg_positive = sum(s["positive"] * w for s, w in zip(sentiments, weights)) / total_weight
        avg_negative = sum(s["negative"] * w for s, w in zip(sentiments, weights)) / total_weight
        avg_neutral = sum(s["neutral"] * w for s, w in zip(sentiments, weights)) / total_weight
        avg_composite = avg_positive - avg_negative
        avg_confidence = sum(s["confidence"] * w for s, w in zip(sentiments, weights)) / total_weight

        result = {
            "symbol": symbol,
            "positive": round(avg_positive, 4),
            "negative": round(avg_negative, 4),
            "neutral": round(avg_neutral, 4),
            "composite": round(avg_composite, 4),
            "confidence": round(avg_confidence, 4),
            "timestamp": datetime.utcnow().isoformat()
        }

        # Cache in Redis (5-minute TTL)
        cache_key = f"sentiment:{symbol}"
        await self.redis_client.setex(
            cache_key,
            300,
            json.dumps(result)
        )

        log.info("sentiment_calculated", symbol=symbol, composite=avg_composite, confidence=avg_confidence)

        return result

    async def update_all_symbols(self):
        """Update sentiment for all symbols (background task)"""
        symbols = ["EURUSD", "GBPUSD", "USDJPY", "USDCAD", "XAUUSD"]

        for symbol in symbols:
            try:
                await self.get_symbol_sentiment(symbol)
            except Exception as e:
                log.error("sentiment_update_failed", symbol=symbol, error=str(e))

    async def run_periodic_updates(self):
        """Run sentiment updates every 5 minutes"""
        while True:
            try:
                log.info("periodic_update_start")
                await self.update_all_symbols()
                log.info("periodic_update_complete")
            except Exception as e:
                log.error("periodic_update_failed", error=str(e))

            # Wait 5 minutes
            await asyncio.sleep(300)

    async def heartbeat(self):
        """Send heartbeat to Redis"""
        while True:
            try:
                await self.redis_client.setex("heartbeat:finbert", 120, "alive")
            except Exception as e:
                log.error("heartbeat_failed", error=str(e))

            await asyncio.sleep(60)

# ==================== Main ====================

async def main():
    """Main entry point"""
    log.info("finbert_service_starting")

    service = SentimentService()
    await service.connect_redis()

    # Start background tasks
    tasks = [
        asyncio.create_task(service.run_periodic_updates()),
        asyncio.create_task(service.heartbeat())
    ]

    log.info("finbert_service_running")

    # Wait for tasks
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
