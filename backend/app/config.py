from pathlib import Path
from typing import Literal
from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parents[1]

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / '.env', extra='ignore')
    provider: Literal['mock', 'openai'] = 'mock'
    service_token: SecretStr = SecretStr('')
    openai_api_key: SecretStr = SecretStr('')
    openai_model: str = ''  # Explicitly configured; never use the coding agent model implicitly
    openai_base_url: str = 'https://api.openai.com/v1'
    ai_timeout_seconds: float = Field(default=45, ge=1, le=120)
    max_image_bytes: int = Field(default=8 * 1024 * 1024, ge=1024, le=20 * 1024 * 1024)
    requests_per_minute: int = Field(default=20, ge=1, le=120)
