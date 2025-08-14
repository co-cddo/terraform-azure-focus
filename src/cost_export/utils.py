import os

def _get_required_env(name):
    value = os.environ.get(name)
    if not value:
        raise EnvironmentError(f"Missing required environment variable: {name}")
    return value

class Config:    
    client_id = _get_required_env("ENTRA_APP_CLIENT_ID")  # Example: "00000000-0000-0000-0000-000000000000"
    urn = _get_required_env("ENTRA_APP_URN")  # Example: "api://AWS-Federation-App"
    arn = _get_required_env("AWS_ROLE_ARN")  # Example: "arn:aws:iam::000000000000:role/aad_s3"
    s3_focus_path = _get_required_env("S3_FOCUS_PATH")  # Example: "s3://s3bucketname/test/"
    aws_region = _get_required_env("AWS_REGION")  # Example: "eu-west-2"
    storage_connection_string = _get_required_env("STORAGE_CONNECTION_STRING")
    container_name = _get_required_env("CONTAINER_NAME")
    utilization_container_name = _get_required_env("UTILIZATION_CONTAINER_NAME")
    s3_utilization_path = _get_required_env("S3_UTILIZATION_PATH")
    s3_carbon_path = _get_required_env("S3_CARBON_PATH")
    carbon_directory_name = _get_required_env("CARBON_DIRECTORY_NAME")

    # Carbon Optimization API settings
    carbon_tenant_id = os.environ.get("CARBON_API_TENANT_ID")
    billing_scope = os.environ.get("BILLING_SCOPE")