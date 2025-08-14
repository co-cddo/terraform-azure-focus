import logging
import azure.functions as func
from cost_export.utils import Config, getS3FileSystem, is_uuid
import pyarrow.parquet as pq
import io
import json
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone

app = func.FunctionApp()
 
@app.function_name(name="CostExportProcessor")
@app.queue_trigger(arg_name="msg", queue_name="costdata", connection="StorageAccountManagedIdentity")
def cost_export_processor(msg: func.QueueMessage) -> None:
    """Queue trigger function that processes parquet files when messages are received"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logging.info(f'Cost export processor triggered at: {utc_timestamp}')
    logging.info(f'Processing message: {msg.get_body().decode("utf-8")}')
    
    try:
        # Parse the EventGrid message to get the specific blob
        message_body = json.loads(msg.get_body().decode("utf-8"))
        blob_url = message_body.get("subject")
        if not blob_url:
           # log an error
           return
        
        # Extract blob name from the subject (format: /blobServices/default/containers/{container}/blobs/{blobname})
        blob_name = None
        if blob_url.startswith("/blobServices/default/containers/"):
            parts = blob_url.split("/blobs/", 1)
            if len(parts) == 2:
                blob_name = parts[1]
        
        if not blob_name:
            logging.error(f"Could not extract blob name from message subject: {blob_url}")
            return
            
        if not blob_name.endswith('.parquet'):
            logging.info(f"Skipping non-parquet file: {blob_name}")
            return
            
        logging.info(f"Processing specific parquet file: {blob_name}")
        
        # Initialize blob service client
        blob_service_client = BlobServiceClient.from_connection_string(Config.storage_connection_string)
        container_client = blob_service_client.get_container_client(Config.container_name)
        
        # Get S3 filesystem
        s3 = getS3FileSystem()
        
        # Process the specific blob from the message
        try:
            # Download blob content
            blob_client = container_client.get_blob_client(blob_name)
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
            # Example: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/focus-backfill-2025-06/billing_period=20250601/202508131031/part_0_0001.parquet
            # Becomes: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/billing_period=20250601/part_0_0001.parquet
            path_parts = blob_name.split('/')
            modified_parts = []
            
            for part in path_parts:
                if part == "focus-daily-cost-export":
                    # Skip this part entirely
                    continue
                elif part.startswith("focus-backfill-"):
                    # Skip focus-backfill-YYYY-MM directories
                    logging.info(f"Skipping focus-backfill directory: {part}")
                    continue
                elif len(part) == 12 and part.isdigit():
                    # Validate that this is actually a valid YYYYMMDDHHMM timestamp
                    try:
                        datetime.strptime(part, "%Y%m%d%H%M")
                        logging.info(f"Skipping timestamp directory: {part}")
                        continue
                    except ValueError:
                        # Not a valid timestamp, continue processing normally
                        pass
                elif "-" in part and len(part) == 17 and part[:8].isdigit() and part[9:17].isdigit():
                    # Transform date range (e.g., "20250801-20250831" -> "billing_period=20250801")
                    billing_period = part.split("-")[0]
                    modified_parts.append(f"billing_period={billing_period}")
                elif is_uuid(part):
                    # Skip UUID directories
                    logging.info(f"Skipping UUID directory: {part}")
                    continue
                else:
                    modified_parts.append(part)
            
            modified_path = '/'.join(modified_parts)
            s3_path = f"{Config.s3_focus_path.rstrip('/')}/{modified_path.lstrip('/')}"
            pq.write_table(table, where=s3_path, filesystem=s3, compression='snappy')
            logging.info(f"Successfully uploaded {blob_name} to S3 at path: {s3_path}")

            # Delete source file after successful upload
            blob_client.delete_blob()
            logging.info(f"Successfully deleted source file: {blob_name}")
            
        except Exception as e:
            logging.error(f"Failed to process {blob_name}: {str(e)}")
            raise
            
    except Exception as e:
        logging.error(f"Error in daily cost export processor: {str(e)}")
        raise
