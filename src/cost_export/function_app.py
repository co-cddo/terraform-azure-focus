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
 
@app.schedule(schedule="0 0 9 * * *", arg_name="timer", run_on_startup=False, use_monitor=False)
def daily_cost_export_processor(timer: func.TimerRequest) -> None:
    """Timer trigger function that runs daily at 9:00 AM UTC to process parquet files"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    if timer.past_due:
        logging.info('The timer is past due!')

    logging.info(f'Daily cost export processor executed at: {utc_timestamp}')
    
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
                    ### End of deployment specific requirements ###
                    
                    # Write to S3
                    s3_path = f"{target_file_path.rstrip('/')}/{blob.name}"
                    pq.write_to_dataset(table, root_path=s3_path, filesystem=s3, compression='snappy')
                    logging.info(f"Successfully uploaded {blob.name} to S3")
                    
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
