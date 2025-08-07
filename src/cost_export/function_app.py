import logging
import os
import azure.functions as func
import pyarrow.parquet as pq
import pandas as pd
import io
import boto3
from azure.identity import ManagedIdentityCredential
from pyarrow.fs import S3FileSystem
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone

# Environment variables - examples of expected values:
client_id = os.environ.get("ENTRA_APP_CLIENT_ID")  # Example: "00000000-0000-0000-0000-000000000000"
urn = os.environ.get("ENTRA_APP_URN")  # Example: "api://AWS-Federation-App"
arn = os.environ.get("AWS_ROLE_ARN")  # Example: "arn:aws:iam::000000000000:role/aad_s3"
target_file_path = os.environ.get("S3_TARGET_PATH")  # Example: "s3://s3bucketname/test/"
aws_region = os.environ.get("AWS_REGION")  # Example: "eu-west-2"
storage_connection_string = os.environ.get("STORAGE_CONNECTION_STRING")
container_name = os.environ.get("CONTAINER_NAME")
 
app = func.FunctionApp()
 
@app.function_name(name="CostExportProcessor")
@app.queue_trigger(arg_name="msg", queue_name="costdata", connection="StorageAccountManagedIdentity")
def cost_export_processor(msg: func.QueueMessage) -> None:
    """Queue trigger function that processes parquet files when messages are received"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logging.info(f'Cost export processor triggered at: {utc_timestamp}')
    logging.info(f'Processing message: {msg.get_body().decode("utf-8")}')
    
    try:
        # Initialize blob service client
        blob_service_client = BlobServiceClient.from_connection_string(storage_connection_string)
        container_client = blob_service_client.get_container_client(container_name)
        
        # Get S3 filesystem
        s3 = getS3FileSystem()
        
        # Find and process all parquet files
        processed_files = []
        failed_files = []
        
        # List all blobs in container recursively
        blobs = container_client.list_blobs()
        
        for blob in blobs:
            if blob.name.endswith('.parquet'):
                try:
                    logging.info(f"Processing parquet file: {blob.name}")
                    
                    # Download blob content
                    blob_client = container_client.get_blob_client(blob.name)
                    blob_data = blob_client.download_blob().readall()
                    blob_to_read = io.BytesIO(blob_data)
                    
                    # Read parquet table
                    table = pq.read_table(blob_to_read)
                    
                    ### Any deployment specific requirements can be implemented here ###
                    table = table.drop_columns("ResourceName")
                    table = table.drop_columns("BillingAccountId")
                    table = table.drop_columns("BillingAccountName")
                    table = table.drop_columns("BillingAccountType")
                    table = table.drop_columns("ChargeDescription")
                    table = table.drop_columns("CommitmentDiscountName")
                    table = table.drop_columns("RegionId")
                    table = table.drop_columns("ResourceId")
                    table = table.drop_columns("SubAccountId")
                    table = table.drop_columns("SubAccountName")
                    table = table.drop_columns("SubAccountType")
                    table = table.drop_columns("Tags")
                    
                    # Drop any columns that start with "x_"
                    columns_to_drop = [col for col in table.column_names if col.startswith("x_")]
                    if columns_to_drop:
                        table = table.drop_columns(columns_to_drop)
                    ### End of deployment specific requirements ###
                    
                    # Transform S3 path
                    # Example: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/focus-daily-cost-export/20250801-20250831/part_0_0001.parquet
                    # Becomes: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/billing_period=20250801/part_0_0001.parquet
                    path_parts = blob.name.split('/')
                    modified_parts = []
                    
                    for part in path_parts:
                        if part == "focus-daily-cost-export":
                            # Skip this part entirely
                            continue
                        elif "-" in part and len(part) == 17 and part[:8].isdigit() and part[9:17].isdigit():
                            # Transform date range (e.g., "20250801-20250831" -> "billing_period=20250801")
                            billing_period = part.split("-")[0]
                            modified_parts.append(f"billing_period={billing_period}")
                        elif len(part) == 36 and part.count('-') == 4 and all(c.isalnum() or c == '-' for c in part):
                            # Skip GUID directories (format: 8-4-4-4-12 characters)
                            logging.info(f"Skipping GUID directory: {part}")
                            continue
                        else:
                            modified_parts.append(part)
                    
                    modified_path = '/'.join(modified_parts)
                    s3_path = f"{target_file_path.rstrip('/')}/{modified_path}"
                    pq.write_table(table, where=s3_path, filesystem=s3, compression='snappy')
                    logging.info(f"Successfully uploaded {blob.name} to S3 at path: {s3_path}")
                    
                    # Delete source file after successful upload
                    blob_client.delete_blob()
                    logging.info(f"Successfully deleted source file: {blob.name}")
                    
                    processed_files.append(blob.name)
                    
                except Exception as e:
                    logging.error(f"Failed to process {blob.name}: {str(e)}")
                    failed_files.append({"file": blob.name, "error": str(e)})
                    continue
        
        # Summary logging
        logging.info(f"Processing complete. Successfully processed: {len(processed_files)} files")
        if failed_files:
            logging.warning(f"Failed to process: {len(failed_files)} files - {failed_files}")
        
        if not processed_files and not failed_files:
            logging.info("No parquet files found to process")
            
    except Exception as e:
        logging.error(f"Error in daily cost export processor: {str(e)}")
        raise

def getS3FileSystem():
    default_credential = ManagedIdentityCredential()
    token = default_credential.get_token(urn)

    role = boto3.client('sts').assume_role_with_web_identity(
        RoleArn=arn,
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
        region=aws_region
    )
