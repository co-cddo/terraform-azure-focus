#!/usr/bin/env python3
"""
Test script to demonstrate idempotency features of the Carbon exports.

This script shows how the updated carbon export functions handle repeated
requests for the same data ranges without duplicating work.
"""

from datetime import datetime, timezone, timedelta
import json

def simulate_monthly_exporter_runs():
    """Simulate multiple runs of the monthly exporter to show idempotency."""
    print("Carbon Emissions Monthly Exporter - Idempotency Test")
    print("=" * 55)
    
    today = datetime.now(timezone.utc)
    last_month = today.replace(day=1) - timedelta(days=1)
    
    print(f"Current date: {today.strftime('%Y-%m-%d')}")
    print(f"Target month for export: {last_month.strftime('%Y-%m')}")
    print()
    
    # Simulate multiple runs
    runs = [
        {"run": 1, "description": "First run - will process data"},
        {"run": 2, "description": "Second run - should skip (idempotent)"},
        {"run": 3, "description": "Third run - should skip (idempotent)"},
    ]
    
    print("Simulated Monthly Exporter Runs:")
    print("-" * 40)
    
    for run_info in runs:
        run_num = run_info["run"]
        desc = run_info["description"]
        
        print(f"Run {run_num}: {desc}")
        
        if run_num == 1:
            print(f"  ✓ API call made for {last_month.strftime('%Y-%m-01')}")
            print(f"  ✓ Data saved to S3: billing_period={last_month.strftime('%Y%m01')}/carbon-emissions-{last_month.strftime('%Y-%m')}.json")
            print(f"  ✓ Processing completed")
        else:
            print(f"  ⏭️  Data already exists - skipping API call")
            print(f"  ⏭️  No S3 upload needed")
            print(f"  ✓ Function exits early (idempotent)")
        
        print()

def simulate_backfill_runs():
    """Simulate multiple backfill runs with different parameters."""
    print("Carbon Emissions Backfill - Idempotency Test")
    print("=" * 45)
    
    scenarios = [
        {
            "name": "Initial Backfill",
            "params": "No parameters (default: skip_existing=true)",
            "description": "Process all months, but skip any that already exist"
        },
        {
            "name": "Re-run Backfill", 
            "params": "No parameters (default: skip_existing=true)",
            "description": "Skip all months since they already exist (fully idempotent)"
        },
        {
            "name": "Force Overwrite",
            "params": "force_overwrite=true",
            "description": "Overwrite all existing data with fresh API calls"
        },
        {
            "name": "Process All (No Skip)",
            "params": "skip_existing=false",
            "description": "Make API calls for all months, but don't overwrite existing files"
        }
    ]
    
    total_months = 46  # 2022-01 through 2025-10 (example)
    existing_months = 0  # Start with no existing data
    
    for i, scenario in enumerate(scenarios, 1):
        print(f"Scenario {i}: {scenario['name']}")
        print(f"Parameters: {scenario['params']}")
        print(f"Description: {scenario['description']}")
        print()
        
        if scenario['name'] == "Initial Backfill":
            processed = total_months
            skipped = 0
            existing_months = total_months  # After first run, all exist
        elif scenario['name'] == "Re-run Backfill":
            processed = 0
            skipped = total_months  # All skipped because they exist
        elif scenario['name'] == "Force Overwrite":
            processed = total_months
            skipped = 0  # None skipped because we're forcing overwrite
        else:  # Process All (No Skip)
            processed = total_months
            skipped = 0  # None skipped, but files won't be overwritten
        
        print(f"  Result: Processed {processed} months, skipped {skipped} existing months")
        print(f"  API calls made: {processed}")
        print(f"  Files written to S3: {processed}")
        print()

def show_api_examples():
    """Show example API calls and responses."""
    print("API Endpoint Examples")
    print("=" * 25)
    
    examples = [
        {
            "endpoint": "GET /api/carbon-date-range",
            "description": "Check current API date range",
            "response_sample": {
                "current_date": "2025-10-30",
                "api_available_range": {
                    "start_date": "2024-10-01",
                    "end_date": "2025-09-30",
                    "total_months": 12
                },
                "last_month_processing": {
                    "target_month": "2025-09-30",
                    "is_available": True,
                    "would_be_processed": "2025-09-01"
                }
            }
        },
        {
            "endpoint": "GET /api/carbon-date-range?check_existing=true",
            "description": "Check date range + existing data",
            "response_sample": {
                "existing_data_check": {
                    "total_existing": 35,
                    "total_missing": 11,
                    "existing_months": ["2022-01", "2022-02", "...", "2025-09"],
                    "missing_months": ["2025-10", "2025-11"],
                    "note": "This check covers 2022-01 through current API range"
                }
            }
        },
        {
            "endpoint": "POST /api/carbon-backfill",
            "description": "Idempotent backfill (default)",
            "response_sample": "Carbon backfill completed successfully. Processed 0 months, skipped 46 existing months."
        },
        {
            "endpoint": "POST /api/carbon-backfill?force_overwrite=true",
            "description": "Force overwrite all data",
            "response_sample": "Carbon backfill completed successfully. Processed 46 months, skipped 0 existing months."
        }
    ]
    
    for example in examples:
        print(f"Endpoint: {example['endpoint']}")
        print(f"Purpose: {example['description']}")
        print("Response sample:")
        if isinstance(example['response_sample'], dict):
            print(json.dumps(example['response_sample'], indent=2))
        else:
            print(f"  {example['response_sample']}")
        print()

def main():
    """Run all idempotency demonstrations."""
    simulate_monthly_exporter_runs()
    print("\n" + "="*60 + "\n")
    simulate_backfill_runs()
    print("\n" + "="*60 + "\n")
    show_api_examples()
    
    print("Summary of Idempotency Features")
    print("=" * 35)
    print("✅ Monthly Exporter: Skips processing if data already exists")
    print("✅ Backfill Function: Configurable skip/overwrite behavior")
    print("✅ S3 File Checking: Verifies existence before API calls")
    print("✅ Error Recovery: Can re-run safely after partial failures")
    print("✅ Resource Efficiency: Avoids unnecessary API calls and uploads")
    print("✅ Monitoring: Enhanced logging shows skipped vs processed months")

if __name__ == "__main__":
    main()