import os
import boto3
import logging
import requests
import uuid
from pyarrow.fs import S3FileSystem
from azure.identity import ManagedIdentityCredential

def _get_required_env(name):
    value = os.environ.get(name)
    if not value:
        raise EnvironmentError(f"Missing required environment variable: {name}")
    return value

def is_uuid(value):
    """Check if a string is a valid UUID"""
    try:
        uuid.UUID(value)
        return True
    except ValueError:
        return False

class Config:    
    client_id = _get_required_env("ENTRA_APP_CLIENT_ID")  # Example: "00000000-0000-0000-0000-000000000000"
    urn = _get_required_env("ENTRA_APP_URN")  # Example: "api://AWS-Federation-App"
    arn = _get_required_env("AWS_ROLE_ARN")  # Example: "arn:aws:iam::000000000000:role/aad_s3"
    s3_focus_path = _get_required_env("S3_FOCUS_PATH")  # Example: "s3://s3bucketname/test/"
    aws_region = _get_required_env("AWS_REGION")  # Example: "eu-west-2"
    storage_connection_string = _get_required_env("STORAGE_CONNECTION_STRING")
    container_name = _get_required_env("CONTAINER_NAME")
    s3_utilization_path = _get_required_env("S3_UTILIZATION_PATH")
    s3_recommendations_path = _get_required_env("S3_RECOMMENDATIONS_PATH")
    s3_carbon_path = _get_required_env("S3_CARBON_PATH")
    carbon_directory_name = _get_required_env("CARBON_DIRECTORY_NAME")

    # Carbon Optimization API settings
    carbon_tenant_id = os.environ.get("CARBON_API_TENANT_ID")
    billing_scope = os.environ.get("BILLING_SCOPE")

def getS3FileSystem():
    default_credential = ManagedIdentityCredential()
    token = default_credential.get_token(Config.urn)

    role = boto3.client('sts').assume_role_with_web_identity(
        RoleArn=Config.arn,
        RoleSessionName='session1',
        WebIdentityToken=token.token
        )
        
    credentials = role['Credentials']
    aws_access_key_id = credentials['AccessKeyId']
    aws_secret_access_key = credentials['SecretAccessKey']
    aws_session_token = credentials['SessionToken']
        
    return S3FileSystem(
        access_key=aws_access_key_id,
        secret_key=aws_secret_access_key,
        session_token=aws_session_token,
        region=Config.aws_region
    )

def extract_subscription_ids_from_management_group(scope):
    """Extract all subscription IDs from a management group scope"""
    try:
        # Get access token using managed identity
        credential = ManagedIdentityCredential()
        token = credential.get_token("https://management.azure.com/.default")
        
        headers = {
            "Authorization": f"Bearer {token.token}",
            "Content-Type": "application/json"
        }
        
        # Validate that this is a management group scope
        if "/providers/Microsoft.Management/managementGroups/" not in scope:
            logging.error(f"Expected management group scope, got: {scope}")
            return []
        
        # Get all subscriptions under this management group
        subscription_ids = get_subscriptions_from_management_group(scope, headers)
        
        logging.info(f"Found {len(subscription_ids)} subscriptions in management group")
        return subscription_ids
        
    except Exception as e:
        logging.error(f"Error extracting subscription IDs: {str(e)}")
        return []


def get_subscriptions_from_management_group(scope, headers):
    """Get all subscription IDs from a management group scope using Resource Graph API"""
    try:
        # Extract management group ID from scope
        # Format: /providers/Microsoft.Management/managementGroups/{managementGroupId}
        mg_id = scope.split("/")[-1]
        
        # Use Resource Graph API to get subscriptions under management group
        subscription_ids = get_subscriptions_via_resource_graph(mg_id, headers)
        
        logging.info(f"Retrieved {len(subscription_ids)} subscriptions from management group {mg_id}")
        return subscription_ids
            
    except Exception as e:
        logging.error(f"Error getting subscriptions from management group: {str(e)}")
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
                    
            logging.info(f"Resource Graph API found {len(subscription_ids)} subscriptions under management group {mg_id}")
            return subscription_ids
            
        else:
            logging.error(f"Resource Graph API failed: {response.status_code} - {response.text}")
            return []
            
    except Exception as e:
        logging.error(f"Error using Resource Graph API: {str(e)}")
        return []