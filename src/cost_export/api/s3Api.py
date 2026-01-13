from pyarrow.fs import S3FileSystem
from common import (
    Config,
)
from api.tokens import (
    TokenManager,
)
import logging
import os
logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

def getS3FileSystem():
  credentials = TokenManager().aws_identity

  aws_access_key_id = credentials['aws_access_key_id']
  aws_secret_access_key = credentials['aws_secret_access_key']
  aws_session_token = credentials['aws_session_token']
      
  return S3FileSystem(
      access_key=aws_access_key_id,
      secret_key=aws_secret_access_key,
      session_token=aws_session_token,
      region=Config.aws_region
  )
