from pathlib import Path
from typing import Literal
from pydantic import Field, SecretStr, field_validator
from urllib.parse import urlsplit
from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parents[1]

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / '.env', extra='ignore')
    provider: Literal['mock', 'openai', 'deepseek'] = 'mock'
    service_token: SecretStr = SecretStr('')
    openai_api_key: SecretStr = SecretStr('')
    openai_model: str = ''  # Explicitly configured; never use the coding agent model implicitly
    openai_base_url: str = 'https://api.openai.com/v1'
    deepseek_api_key: SecretStr = SecretStr('')
    deepseek_model: str = ''
    deepseek_vision_model: str = ''  # Optional photo model; otherwise use deepseek_model.
    deepseek_base_url: str = 'https://api.deepseek.com'
    ai_max_output_tokens: int = Field(default=12000, ge=256, le=16000)
    ai_timeout_seconds: float = Field(default=45, ge=1, le=120)
    max_image_bytes: int = Field(default=8 * 1024 * 1024, ge=1024, le=20 * 1024 * 1024)
    requests_per_minute: int = Field(default=20, ge=1, le=120)

    @field_validator('openai_base_url', 'deepseek_base_url')
    @classmethod
    def secure_endpoint(cls, value: str) -> str:
        url = urlsplit(value)
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise ValueError('模型服务地址必须使用不含凭据的 HTTPS URL')
        return value.rstrip('/')

    def ai_configuration(self, photo: bool = False) -> tuple[SecretStr, str, str]:
        if self.provider == 'deepseek':
            model = (self.deepseek_vision_model or self.deepseek_model) if photo else self.deepseek_model
            return self.deepseek_api_key, model.strip(), self.deepseek_base_url
        return self.openai_api_key, self.openai_model.strip(), self.openai_base_url

    def configuration_issues(self, photo: bool = False) -> list[str]:
        if self.provider == 'mock':
            return []
        key, model, _ = self.ai_configuration(photo)
        prefix = 'DEEPSEEK' if self.provider == 'deepseek' else 'OPENAI'
        issues = []
        if not key.get_secret_value().strip(): issues.append(f'后端缺少 {prefix}_API_KEY')
        if not model: issues.append(f'后端缺少 {prefix}_MODEL')
        if self.provider == 'deepseek' and photo and model and model not in {
            'deepseek-flash', 'deepseek-v4-flash', 'deepseek-v4-flash-vision-exp'
        }:
            issues.append('照片分析请设置 DEEPSEEK_VISION_MODEL=deepseek-flash；当前模型未核实支持图片')
        return issues
