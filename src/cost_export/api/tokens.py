###
# uses two local ENV VAR to override default behaviour allowing code to be ran locally
#  AWS_TOKEN
#  AZURE_TOKEN
###
import logging
from azure.identity import ManagedIdentityCredential
from common import (
  _get_required_env,
  getS3FileSystem,
  Config,
)

logger = logging.getLogger("cost_export")

class TokenManager:
  _instance = None
  _s3FileSystem = None
  _azureToken: str = None
  
  def __new__(cls):
    if cls._instance is None:
        cls._instance = super().__new__(cls)
    return cls._instance

  @property
  def s3_token(self):
    AWS_TOKEN = _get_required_env("AWS_TOKEN")
    if AWS_TOKEN:
       return AWS_TOKEN

    if self._s3FileSystem is None:
      try:
        self._s3FileSystem = getS3FileSystem()
      except Exception as e:
        logger.error(f"Failed to get S3 file system: {e}")
    
    logger.debug(f"s3_token: AWS token: ", self._azureToken)
    return self._s3FileSystem
  
  @property
  def azure_token(self) -> str:
    AZURE_TOKEN = _get_required_env("AZURE_TOKEN")
    if AZURE_TOKEN:
       return AZURE_TOKEN
    
    if self._azureToken is None:
      try:
        credential = ManagedIdentityCredential()
        token = credential.get_token("https://management.azure.com/.default")
        self._azureToken = token.token
      except Exception as e:
        logger.error(f"Failed to get azure api token: {e}")

    logger.debug(f"azure_token: management API token: ", self._azureToken)
    return self._azureToken
