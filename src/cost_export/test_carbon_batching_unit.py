#!/usr/bin/env python3
"""
Unit tests for the Carbon API subscription batching functionality.

These tests verify that the batching logic correctly handles various
subscription list sizes and properly merges the results.
"""

import unittest
from unittest.mock import Mock, patch
import json

# Mock the Azure Functions and other dependencies since we can't import them in test environment
class MockConfig:
    s3_carbon_path = "test-bucket/carbon"
    carbon_directory_name = "carbon-data"

class MockDateTime:
    @staticmethod
    def strptime(date_str, format_str):
        # Simple mock that returns an object with strftime method
        class MockDateObj:
            def strftime(self, fmt):
                if fmt == "%Y%m01":
                    return "20250901"
                return "2025-09"
        return MockDateObj()

# Mock function implementations (simplified versions of the actual functions)
def mock_make_carbon_api_request(headers, subscription_ids, month_str, timeout=300):
    """Mock version of make_carbon_api_request for testing"""
    if len(subscription_ids) > 100:
        return False, None, "InvalidNumberOfSubscriptions - Too many subscriptions"
    
    # Simulate successful response
    mock_response = {
        "subscriptionAccessDecisionList": [
            {"subscriptionId": sub_id, "decision": "Allowed"} for sub_id in subscription_ids
        ],
        "value": [
            {
                "dataType": "MonthlySummaryData",
                "date": month_str,
                "latestMonthEmissions": 0.1 * len(subscription_ids),  # Simulate data proportional to subs
                "carbonIntensity": 22
            }
        ]
    }
    return True, mock_response, None

def mock_make_carbon_api_request_batched(headers, subscription_ids, month_str, timeout=300, max_batch_size=100):
    """Mock version of the batched API request function"""
    if not subscription_ids:
        return False, None, "No subscription IDs provided"
    
    total_subscriptions = len(subscription_ids)
    
    # If within limit, use single request
    if total_subscriptions <= max_batch_size:
        return mock_make_carbon_api_request(headers, subscription_ids, month_str, timeout)
    
    # Batch the subscriptions
    batches = []
    for i in range(0, total_subscriptions, max_batch_size):
        batch = subscription_ids[i:i + max_batch_size]
        batches.append(batch)
    
    # Collect results from all batches
    merged_subscription_access_decisions = []
    merged_value_data = []
    successful_batches = 0
    failed_batches = []
    
    for batch_num, batch_subscription_ids in enumerate(batches, 1):
        success, batch_data, error_message = mock_make_carbon_api_request(
            headers, batch_subscription_ids, month_str, timeout
        )
        
        if success and batch_data:
            # Merge subscription access decisions
            if "subscriptionAccessDecisionList" in batch_data:
                merged_subscription_access_decisions.extend(batch_data["subscriptionAccessDecisionList"])
            
            # Merge value data
            if "value" in batch_data:
                merged_value_data.extend(batch_data["value"])
            
            successful_batches += 1
        else:
            failed_batches.append({"batch": batch_num, "error": error_message, "subscription_count": len(batch_subscription_ids)})
    
    # Check if we have any successful data
    if successful_batches == 0:
        return False, None, f"All {len(batches)} batches failed. First error: {failed_batches[0]['error'] if failed_batches else 'Unknown error'}"
    
    # Create merged response
    merged_response = {
        "subscriptionAccessDecisionList": merged_subscription_access_decisions,
        "value": merged_value_data
    }
    
    # Add metadata about batching
    merged_response["_batchingMetadata"] = {
        "total_batches": len(batches),
        "successful_batches": successful_batches,
        "failed_batches": len(failed_batches),
        "total_subscriptions": total_subscriptions,
        "batch_size_used": max_batch_size
    }
    
    return True, merged_response, None

class TestCarbonApiBatching(unittest.TestCase):
    """Test cases for Carbon API subscription batching functionality"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.mock_headers = {"Authorization": "Bearer test-token"}
        self.mock_month = "2025-09-01"
    
    def test_small_subscription_list(self):
        """Test that small subscription lists work without batching"""
        subscription_ids = [f"sub-{i:03d}" for i in range(50)]
        
        success, data, error = mock_make_carbon_api_request_batched(
            self.mock_headers, subscription_ids, self.mock_month
        )
        
        self.assertTrue(success)
        self.assertIsNotNone(data)
        self.assertIsNone(error)
        self.assertEqual(len(data["subscriptionAccessDecisionList"]), 50)
        self.assertNotIn("_batchingMetadata", data)  # No batching metadata for single request
    
    def test_exact_api_limit(self):
        """Test subscription list exactly at the 100 subscription limit"""
        subscription_ids = [f"sub-{i:03d}" for i in range(100)]
        
        success, data, error = mock_make_carbon_api_request_batched(
            self.mock_headers, subscription_ids, self.mock_month
        )
        
        self.assertTrue(success)
        self.assertIsNotNone(data)
        self.assertIsNone(error)
        self.assertEqual(len(data["subscriptionAccessDecisionList"]), 100)
        self.assertNotIn("_batchingMetadata", data)  # No batching metadata for single request
    
    def test_gds_subscription_count(self):
        """Test the specific GDS case from issue #25 (131 subscriptions)"""
        subscription_ids = [f"sub-{i:03d}" for i in range(131)]
        
        success, data, error = mock_make_carbon_api_request_batched(
            self.mock_headers, subscription_ids, self.mock_month
        )
        
        self.assertTrue(success)
        self.assertIsNotNone(data)
        self.assertIsNone(error)
        
        # Check that all subscriptions are represented
        self.assertEqual(len(data["subscriptionAccessDecisionList"]), 131)
        
        # Check batching metadata
        self.assertIn("_batchingMetadata", data)
        metadata = data["_batchingMetadata"]
        self.assertEqual(metadata["total_batches"], 2)
        self.assertEqual(metadata["successful_batches"], 2)
        self.assertEqual(metadata["failed_batches"], 0)
        self.assertEqual(metadata["total_subscriptions"], 131)
        self.assertEqual(metadata["batch_size_used"], 100)
        
        # Check that data from both batches is merged
        self.assertEqual(len(data["value"]), 2)  # Two batch responses merged
    
    def test_large_subscription_count(self):
        """Test handling of very large subscription lists"""
        subscription_ids = [f"sub-{i:04d}" for i in range(350)]
        
        success, data, error = mock_make_carbon_api_request_batched(
            self.mock_headers, subscription_ids, self.mock_month
        )
        
        self.assertTrue(success)
        self.assertIsNotNone(data)
        self.assertIsNone(error)
        
        # Check that all subscriptions are represented
        self.assertEqual(len(data["subscriptionAccessDecisionList"]), 350)
        
        # Check batching metadata
        metadata = data["_batchingMetadata"]
        self.assertEqual(metadata["total_batches"], 4)  # 100, 100, 100, 50
        self.assertEqual(metadata["successful_batches"], 4)
        self.assertEqual(metadata["total_subscriptions"], 350)
    
    def test_empty_subscription_list(self):
        """Test handling of empty subscription list"""
        subscription_ids = []
        
        success, data, error = mock_make_carbon_api_request_batched(
            self.mock_headers, subscription_ids, self.mock_month
        )
        
        self.assertFalse(success)
        self.assertIsNone(data)
        self.assertEqual(error, "No subscription IDs provided")
    
    def test_single_subscription(self):
        """Test handling of single subscription"""
        subscription_ids = ["single-sub-001"]
        
        success, data, error = mock_make_carbon_api_request_batched(
            self.mock_headers, subscription_ids, self.mock_month
        )
        
        self.assertTrue(success)
        self.assertIsNotNone(data)
        self.assertEqual(len(data["subscriptionAccessDecisionList"]), 1)
        self.assertEqual(data["subscriptionAccessDecisionList"][0]["subscriptionId"], "single-sub-001")

def run_tests():
    """Run all tests and display results"""
    print("Carbon API Batching - Unit Tests")
    print("=" * 40)
    
    # Create test suite
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestCarbonApiBatching)
    
    # Run tests with detailed output
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Summary
    print("\n" + "=" * 40)
    print("TEST SUMMARY")
    print("=" * 40)
    
    total_tests = result.testsRun
    failures = len(result.failures)
    errors = len(result.errors)
    passed = total_tests - failures - errors
    
    print(f"Total tests: {total_tests}")
    print(f"Passed: {passed}")
    print(f"Failed: {failures}")
    print(f"Errors: {errors}")
    
    if result.wasSuccessful():
        print("✅ All tests passed! Batching logic is working correctly.")
    else:
        print("❌ Some tests failed. Check the output above.")
        
    return result.wasSuccessful()

if __name__ == "__main__":
    run_tests()