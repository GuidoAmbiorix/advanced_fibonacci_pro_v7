import requests
import json

API_KEY = "FA00393FME5LHC8H"
URL = "https://www.alphavantage.co/query"

def get_news_sentiment(tickers=None):
    params = {
        "function": "NEWS_SENTIMENT",
        "limit": 5,
        "apikey": API_KEY
    }
    if tickers:
        params["tickers"] = tickers
        
    try:
        response = requests.get(URL, params=params)
        data = response.json()
        print(json.dumps(data, indent=2))
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    print("Testing Generic News...")
    get_news_sentiment()
    
    print("\nTesting EURUSD News...")
    get_news_sentiment("forex:EURUSD")
