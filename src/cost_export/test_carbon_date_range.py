#!/usr/bin/env python3
"""
Test script to demonstrate the dynamic Carbon API date range calculation.

This script shows how the Carbon Optimization API date range is now calculated
dynamically based on the current date, rather than being hard-coded.
"""

from datetime import datetime, timezone, timedelta

def get_carbon_api_date_range():
    """
    Calculate the available date range for the Carbon Optimization API.
    
    Based on Microsoft documentation:
    - Data for the previous month is available by day 19 of the current month
    - API provides access to up to 12 months of emissions data (rolling window)
    - Data is updated monthly with 12-month retention
    
    Returns:
        tuple: (start_date, end_date) as datetime objects representing the available range
    """
    today = datetime.now(timezone.utc)
    
    # Data for previous month is available by day 19
    # If today is before the 19th, last available data is from 2 months ago
    # If today is on/after the 19th, last available data is from last month
    if today.day >= 19:
        # Latest data available is from last month
        latest_available_month = today.replace(day=1) - timedelta(days=1)  # Last day of previous month
    else:
        # Latest data available is from 2 months ago
        last_month = today.replace(day=1) - timedelta(days=1)  # Last day of previous month
        latest_available_month = last_month.replace(day=1) - timedelta(days=1)  # Last day of month before that
    
    # API provides 12 months of data, so earliest available is 12 months before latest
    earliest_available_month = latest_available_month.replace(day=1)  # First day of latest month
    for _ in range(11):  # Go back 11 more months (total 12 months)
        if earliest_available_month.month == 1:
            earliest_available_month = earliest_available_month.replace(year=earliest_available_month.year - 1, month=12)
        else:
            earliest_available_month = earliest_available_month.replace(month=earliest_available_month.month - 1)
    
    # Convert to first day of earliest month and last day of latest month
    start_date = earliest_available_month
    end_date = latest_available_month
    
    return start_date, end_date

def is_month_within_api_range(target_month):
    """
    Check if a given month is within the Carbon API's available date range.
    
    Args:
        target_month (datetime): The month to check
        
    Returns:
        bool: True if the month is within the available range
    """
    start_date, end_date = get_carbon_api_date_range()
    
    # Convert target_month to first day of month for comparison
    target_first_day = target_month.replace(day=1)
    start_first_day = start_date.replace(day=1)
    end_first_day = end_date.replace(day=1)
    
    return start_first_day <= target_first_day <= end_first_day

def main():
    """Demonstrate the dynamic date range calculation."""
    print("Carbon Optimization API - Dynamic Date Range Calculation")
    print("=" * 60)
    
    today = datetime.now(timezone.utc)
    print(f"Current date: {today.strftime('%Y-%m-%d %H:%M:%S')} UTC")
    print(f"Current day of month: {today.day}")
    print()
    
    # Get the calculated API range
    start_date, end_date = get_carbon_api_date_range()
    
    print("Calculated API Available Range:")
    print(f"  Start: {start_date.strftime('%Y-%m-%d')} (first day of month)")
    print(f"  End:   {end_date.strftime('%Y-%m-%d')} (last day of month)")
    
    # Calculate total months
    total_months = ((end_date.year - start_date.year) * 12 + 
                   (end_date.month - start_date.month) + 1)
    print(f"  Total months available: {total_months}")
    print()
    
    # Show what the monthly exporter would process
    last_month = today.replace(day=1) - timedelta(days=1)
    is_available = is_month_within_api_range(last_month)
    
    print("Monthly Exporter Behavior:")
    print(f"  Target month (previous month): {last_month.strftime('%Y-%m-%d')}")
    print(f"  Is within API range: {is_available}")
    
    if is_available:
        print(f"  Would request: {last_month.strftime('%Y-%m-01')}")
    else:
        if last_month < start_date:
            adjusted_month = start_date
            print(f"  Would use earliest available: {adjusted_month.strftime('%Y-%m-01')}")
        else:
            adjusted_month = end_date
            print(f"  Would use latest available: {adjusted_month.strftime('%Y-%m-01')}")
    print()
    
    # Show calculation logic
    print("Calculation Logic:")
    print("  1. Data for previous month available by day 19 of current month")
    if today.day >= 19:
        print(f"     → Today is day {today.day} (≥19), so last month's data is available")
    else:
        print(f"     → Today is day {today.day} (<19), so only data from 2 months ago is available")
    print("  2. API provides rolling 12-month window of data")
    print("  3. Range is recalculated dynamically on each function execution")
    print()
    
    # Test some example months
    print("Example Month Availability Tests:")
    test_months = [
        datetime(2022, 6, 1, tzinfo=timezone.utc),   # Very old
        datetime(2024, 1, 1, tzinfo=timezone.utc),   # Potentially in range
        datetime(2024, 6, 1, tzinfo=timezone.utc),   # Potentially in range  
        datetime(2024, 12, 1, tzinfo=timezone.utc),  # Potentially in range
        last_month,                                   # Previous month
        today                                        # Current month (shouldn't be available)
    ]
    
    for month in test_months:
        available = is_month_within_api_range(month)
        status = "✓ Available" if available else "✗ Not available"
        print(f"  {month.strftime('%Y-%m')}: {status}")

if __name__ == "__main__":
    main()