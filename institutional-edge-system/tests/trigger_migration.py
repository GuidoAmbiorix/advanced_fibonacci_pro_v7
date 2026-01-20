
import requests
import time

API_URL = "http://localhost:81/api/debug/migrate"

def trigger_migrate():
    print(f"Calling Migration Endpoint: {API_URL}")
    try:
        response = requests.post(API_URL)
        print(f"Status: {response.status_code}")
        try:
            print("Response:", response.json())
        except:
            print("Response Text:", response.text)
            
    except Exception as e:
        print(f"Error calling migration: {e}")

if __name__ == "__main__":
    trigger_migrate()
