###
# uses two local ENV VAR to override default behaviour allowing code to be ran locally
#  AWS:
#    AWS_ACCESS_KEY_ID
#    AWS_SECRET_ACCESS_KEY
#    AWS_SESSION_TOKEN
#  AZURE_TOKEN
###
import os
import logging
import boto3
from azure.identity import ManagedIdentityCredential
from datetime import datetime
from common import (
  Config,
)

logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

class TokenManager:
  _instance = None
  _aws_access_key_id: str = None
  _aws_access_key_secret: str = None
  _aws_session_token: str = None
  _azure_token: str = None
  _azure_token_timestamp = None
  _aws_token_timestamp = None

  def __new__(cls):
    if cls._instance is None:
        cls._instance = super().__new__(cls)
    return cls._instance

  @property
  def aws_identity(self):
    AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID")
    AWS_ACCESS_KEY_SECRET = os.environ.get("AWS_SECRET_ACCESS_KEY")
    AWS_SESSION_TOKEN = os.environ.get("AWS_SESSION_TOKEN")

    if AWS_ACCESS_KEY_ID:
      return {
        "aws_access_key_id": AWS_ACCESS_KEY_ID,
        "aws_secret_access_key": AWS_ACCESS_KEY_SECRET,
        "aws_session_token": AWS_SESSION_TOKEN,
      }

    current_timestamp = datetime.now().timestamp()  # in epoch seconds
    if (self._aws_token_timestamp is None) or ((current_timestamp - self._aws_token_timestamp) > Config.aws_token_timeout_in_seconds):
      try:
        default_credential = ManagedIdentityCredential(client_id=Config.managed_identity_client_id)
        token = default_credential.get_token(Config.urn)

        role = boto3.client('sts').assume_role_with_web_identity(
          RoleArn=Config.arn,
          RoleSessionName='session1',
          WebIdentityToken=token.token
          )
        credentials = role['Credentials']
        self._aws_access_key_id = credentials['AccessKeyId']
        self._aws_access_key_secret = credentials['SecretAccessKey']
        self._aws_session_token = credentials['SessionToken']

        self._aws_token_timestamp = current_timestamp
        logger.info(f"AWS Identity refreshed; expires in {Config.aws_token_timeout_in_seconds} seconds")

      except Exception as e:
        logger.error(f"Failed to get S3 file system: {e}")

    return {
      "aws_access_key_id": self._aws_access_key_id,
      "aws_secret_access_key": self._aws_access_key_secret,
      "aws_session_token": self._aws_session_token,
    }

  @property
  def azure_token(self) -> str:
    AZURE_TOKEN = os.environ.get("AZURE_TOKEN")
    if AZURE_TOKEN:
       return AZURE_TOKEN

    current_timestamp = datetime.now().timestamp()  # in epoch seconds
    if (self._azure_token_timestamp is None) or ((current_timestamp - self._azure_token_timestamp) > Config.azure_token_timeout_in_seconds):
      try:
        credential = ManagedIdentityCredential(client_id=Config.managed_identity_client_id)
        token = credential.get_token("https://management.azure.com/.default")
        self._azure_token = token.token

        self._azure_token_timestamp = current_timestamp
        logger.info(f"Azure API token refreshed; expires in {Config.azure_token_timeout_in_seconds} seconds")

      except Exception as e:
        logger.error(f"Failed to get azure api token: {e}")

    return self._azure_token
