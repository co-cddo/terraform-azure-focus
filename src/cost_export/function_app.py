import logging
import os
import azure.functions as func
import pyarrow.parquet as pq
import pandas as pd
import io
import boto3
from azure.identity import ManagedIdentityCredential
from pyarrow.fs import S3FileSystem

# Environment variables - examples of expected values:
client_id = os.environ.get("ENTRA_APP_CLIENT_ID")  # Example: "00000000-0000-0000-0000-000000000000"
urn = os.environ.get("ENTRA_APP_URN")  # Example: "api://AWS-Federation-App"
arn = os.environ.get("AWS_ROLE_ARN")  # Example: "arn:aws:iam::000000000000:role/aad_s3"
target_file_path = os.environ.get("S3_TARGET_PATH")  # Example: "s3://s3bucketname/test/"
aws_region = os.environ.get("AWS_REGION")  # Example: "eu-west-2"
 
app = func.FunctionApp()
 
@app.blob_trigger(arg_name="costinputdata", path="cost-exports", connection="InputCostDataStorage", source="EventGrid")
def EventGridBlobTrigger(costinputdata: func.InputStream):
    logging.info(f"Python blob trigger function processed blob"
            f"Name: {costinputdata.name}"
            f"Blob Size: {costinputdata.length} bytes")
    if (costinputdata.name.endswith('.parquet')):
        logging.info("Processing parquet file")
        blob_bytes = costinputdata.read()
        blob_to_read = io.BytesIO(blob_bytes)
        
        # read input stream to parquet table
        table = pq.read_table(blob_to_read)

        ### Any deployment specific requirements can be implemented here ###
        table = table.drop_columns("ResourceName")
        ### End of deployment specific requirements ###

        s3 = getS3FileSystem()

        pq.write_to_dataset(table, root_path=f"{target_file_path}/{costinputdata.name}", filesystem=s3, compression='snappy')
        logging.info("Parquet file written to target")

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
