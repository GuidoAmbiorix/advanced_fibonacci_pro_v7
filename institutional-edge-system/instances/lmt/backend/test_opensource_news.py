import datetime

try:
    print("--- Testing ecocal ---")
    import ecocal
    # Ecocal might function differently, checking basic import and usage
    cal = ecocal.Calendar()
    # Get today's date
    today = datetime.date.today()
    
    # Fetch calendar
    events = cal.get_calendar(start_date=today, end_date=today)
    
    if events is not None and not events.empty:
        print(events.head())
        print("R ecocal success")
    else:
        print("R ecocal returned empty data (or None)")
        
except Exception as e:
    print(f"❌ ecocal failed: {e}")
