import logging
import requests
from api.tokens import TokenManager

logger = logging.getLogger("cost_export")

def extract_subscription_ids_from_billing_scope(scope):
    """Extract all subscription IDs that belong to the billing scope"""
    try:
        # Get access token using managed identity
        token = TokenManager().azure_token
        logger.debug(f"cost_mgmt_export_exists: token: {token}")
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        subscription_ids = []
        
        # Parse the billing scope type and extract subscription IDs accordingly
        if "/providers/Microsoft.Billing/billingAccounts/" in scope:
            # Billing Account scope - get all subscriptions under this billing account
            subscription_ids = get_subscriptions_from_billing_account(scope, headers)
            
        elif "/providers/Microsoft.Management/managementGroups/" in scope:
            # Management Group scope - get all subscriptions under this management group
            subscription_ids = get_subscriptions_from_management_group(scope, headers)
            
        elif "/subscriptions/" in scope and scope.count("/") == 2:
            # Single subscription scope - extract the subscription ID directly
            subscription_id = scope.split("/")[2]
            subscription_ids = [subscription_id]
            logger.info(f"Single subscription scope detected: {subscription_id}")
        elif "subscriptions/" in scope and scope.count("/") == 1:
            # Single subscription scope without leading slash - extract the subscription ID directly
            subscription_id = scope.split("/")[1]
            subscription_ids = [subscription_id]
            logger.info(f"Single subscription scope detected (no leading slash): {subscription_id}")
            
        else:
            logger.error(f"Unsupported billing scope format: {scope}")
            return []
        
        logger.info(f"Found {len(subscription_ids)} subscriptions in billing scope")
        return subscription_ids
        
    except Exception as e:
        logger.error(f"Error extracting subscription IDs: {str(e)}")
        return []

def get_subscriptions_from_billing_account(scope, headers):
    """Get all subscription IDs from a billing account scope"""
    try:
        # Extract billing account ID from scope
        # Format: /providers/Microsoft.Billing/billingAccounts/{billingAccountId}
        billing_account_id = scope.split("/")[-1]
        
        # Query billing subscriptions API
        api_url = f"https://management.azure.com/providers/Microsoft.Billing/billingAccounts/{billing_account_id}/billingSubscriptions"
        api_version = "2020-05-01"
        
        response = requests.get(
            f"{api_url}?api-version={api_version}",
            headers=headers,
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            subscription_ids = []
            
            for subscription in data.get("value", []):
                # Extract subscription ID from the subscription properties
                sub_id = subscription.get("properties", {}).get("subscriptionId")
                if sub_id:
                    subscription_ids.append(sub_id)
                    
            logger.info(f"Retrieved {len(subscription_ids)} subscriptions from billing account {billing_account_id}")
            return subscription_ids
            
        else:
            logger.error(f"Failed to get subscriptions from billing account: {response.status_code} - {response.text}")
            return []
            
    except Exception as e:
        logger.error(f"Error getting subscriptions from billing account: {str(e)}")
        return []

def get_subscriptions_from_management_group(scope, headers):
    """Get all subscription IDs from a management group scope using Resource Graph API"""
    try:
        # Extract management group ID from scope
        # Format: /providers/Microsoft.Management/managementGroups/{managementGroupId}
        mg_id = scope.split("/")[-1]
        
        # Use Resource Graph API to get subscriptions under management group
        subscription_ids = get_subscriptions_via_resource_graph(mg_id, headers)
        
        logger.info(f"Retrieved {len(subscription_ids)} subscriptions from management group {mg_id}")
        return subscription_ids
            
    except Exception as e:
        logger.error(f"Error getting subscriptions from management group: {str(e)}")
        return []

def get_subscriptions_via_resource_graph(mg_id, headers):
    """Get subscriptions using Azure Resource Graph API"""
    try:
        # Use Resource Graph to query subscriptions under management group
        api_url = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources"
        api_version = "2021-03-01"
        
        # Query to get all subscriptions under the management group
        query_data = {
            "query": f"ResourceContainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId",
            "managementGroups": [mg_id]
        }
        
        response = requests.post(
            f"{api_url}?api-version={api_version}",
            headers=headers,
            json=query_data,
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            subscription_ids = []
            
            for row in data.get("data", []):
                if "subscriptionId" in row:
                    subscription_ids.append(row["subscriptionId"])
                    
            logger.info(f"Resource Graph API found {len(subscription_ids)} subscriptions under management group {mg_id}")
            return subscription_ids
            
        else:
            logger.error(f"Resource Graph API failed: {response.status_code} - {response.text}")
            return []
            
    except Exception as e:
        logger.error(f"Error using Resource Graph API: {str(e)}")
        return []

def extract_billing_account_from_blob_path(blob_name):
    """Extract billing account ID from the blob path structure
    
    Cost exports create paths like: 
    /gds-focus-v1/focus-daily-cost-export-0/billing_period=20250801/...
    where the export name ends with the billing account index from Terraform
    """
    try:
        path_parts = blob_name.split('/')
        
        for part in path_parts:
            # Look for focus export names that end with a numeric index
            if part.startswith("focus-daily-cost-export-") or part.startswith("focus-backfill-"):
                # Extract the index number from the export name
                if "-" in part:
                    parts = part.split("-")
                    if len(parts) >= 4:  # focus-daily-cost-export-N or focus-backfill-N-YYYY-MM
                        try:
                            # For daily exports: focus-daily-cost-export-0
                            if part.startswith("focus-daily-cost-export-"):
                                export_index = int(parts[-1])
                                return export_index
                            # For backfill exports: focus-backfill-0-2024-01
                            elif part.startswith("focus-backfill-") and len(parts) >= 5:
                                export_index = int(parts[2])  # Third part after focus-backfill-
                                return export_index
                        except (ValueError, IndexError) as e:
                            logging.debug(f"Failed to parse blob path part '{part}': {str(e)}")
                            continue
        
        logger.warning(f"Could not extract billing account index from blob path: {blob_name}")
        return None
        
    except Exception as e:
        logging.exception(f"Error extracting billing account from blob path: {str(e)}")
        return None