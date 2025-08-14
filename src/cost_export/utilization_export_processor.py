import logging
import azure.functions as func
from cost_export.utils import Config, getS3FileSystem
import json
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone

app = func.FunctionApp()

@app.function_name(name="UtilizationExportProcessor")
@app.queue_trigger(arg_name="msg", queue_name="utilizationdata", connection="StorageAccountManagedIdentity")
def utilization_export_processor(msg: func.QueueMessage) -> None:
    """Queue trigger function that processes utilization CSV files when messages are received"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logging.info(f'Utilization export processor triggered at: {utc_timestamp}')
    logging.info(f'Processing message: {msg.get_body().decode("utf-8")}')
    
    try:
        # Parse the EventGrid message to get the specific blob
        message_body = json.loads(msg.get_body().decode("utf-8"))
        blob_url = message_body.get("subject", "")
        
        # Extract blob name from the subject (format: /blobServices/default/containers/{container}/blobs/{blobname})
        blob_name = None
        if blob_url.startswith("/blobServices/default/containers/"):
            parts = blob_url.split("/blobs/", 1)
            if len(parts) == 2:
                blob_name = parts[1]
        
        if not blob_name:
            logging.error(f"Could not extract blob name from message subject: {blob_url}")
            return
            
        if not blob_name.endswith('.csv.gz'):
            logging.info(f"Skipping non-CSV.GZ file: {blob_name}")
            return
            
        logging.info(f"Processing specific utilization CSV.GZ file: {blob_name}")
        
        # Initialize blob service client
        blob_service_client = BlobServiceClient.from_connection_string(Config.storage_connection_string)
        container_client = blob_service_client.get_container_client(Config.utilization_container_name)
        
        # Get S3 filesystem
        s3 = getS3FileSystem()
        
        # Process the specific blob from the message
        try:
            # Download blob content
            blob_client = container_client.get_blob_client(blob_name)
            blob_data = blob_client.download_blob().readall()
            
            # Transform S3 path
            # Example blob_name: utilization-data/utilization-export/20250801-20250831/f2d6918d-67e2-4a1e-b5f6-9a69f1a87160/part_0_0001.csv.gz
            # Final S3 path: {aws_target_file_path}/gds-recommendations-v1/billing_period=20250801/part_0_0001.csv.gz
            path_parts = blob_name.split('/')
            modified_parts = []
            
            for part in path_parts:
                if part in {"utilization-data", "utilization-export"}:

                    # Skip these parts entirely
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
            s3_path = f"{Config.s3_utilization_path.rstrip('/')}/{modified_path}"
            
            # Upload to S3
            with s3.open_output_stream(s3_path) as f:
                f.write(blob_data)
            logging.info(f"Successfully uploaded {blob_name} to S3 at path: {s3_path}")
            
            # Delete source file after successful upload
            blob_client.delete_blob()
            logging.info(f"Successfully deleted source file: {blob_name}")
            
        except Exception as e:
            logging.error(f"Failed to process {blob_name}: {str(e)}")
            raise
            
    except Exception as e:
        logging.error(f"Error in utilization export processor: {str(e)}")
        raise