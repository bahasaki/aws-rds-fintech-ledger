"""
Application configuration.

Reads DATABASE_URL from the environment (populated by the EC2 bootstrap
script's .env file — see terraform/ec2.tf). Never hardcodes credentials
here; this module only knows how to *read* configuration, not generate it.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    app_name: str = "aws-rds-fintech-ledger"
    debug: bool = False


settings = Settings()
