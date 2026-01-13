import os
import boto3
import logging
import requests
import uuid
import json
from azure.identity import ManagedIdentityCredential

logger = logging.getLogger("cost_export")

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
    s3_cost_directory_name = _get_required_env("ROOT_FOLDER_PATH")
    s3_utilization_path = _get_required_env("S3_UTILIZATION_PATH")
    s3_recommendations_path = _get_required_env("S3_RECOMMENDATIONS_PATH")
    s3_carbon_path = _get_required_env("S3_CARBON_PATH")
    carbon_directory_name = _get_required_env("CARBON_DIRECTORY_NAME")

    # backfill
    backfill_start_date = _get_required_env("BACKFILL_START_DATE")
    cost_mgmt_export_container = _get_required_env("STORAGE_CONTAINER")
    cost_mgmt_export_destination_id = _get_required_env("STORAGE_RESOURCE_ID")

    # Carbon Optimization API settings
    carbon_tenant_id = os.environ.get("CARBON_API_TENANT_ID")
    billing_scope = os.environ.get("BILLING_SCOPE")
    billing_azure_location = os.environ.get("BILLING_AZURE_LOCATION")
    
    # Billing account mapping for S3 path organization
    _billing_account_mapping_json = os.environ.get("BILLING_ACCOUNT_MAPPING", "{}")
    try:
        billing_account_mapping = json.loads(_billing_account_mapping_json)
    except:
        logger.warning(f"Failed to parse BILLING_ACCOUNT_MAPPING: {_billing_account_mapping_json}")
        billing_account_mapping = {}
    
    azure_token_timeout_in_seconds = 1800   # 30 minutes
    aws_token_timeout_in_seconds = 900   # 15 minutes
