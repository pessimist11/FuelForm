"""Per-worker resources and admission limits; never retains photos or AI drafts."""
import asyncio
import math
import time
from collections import deque
from contextlib import asynccontextmanager

from .config import Settings
from .providers import DeepSeekProvider, MockProvider, OpenAIProvider, ProviderError


class BackendRuntime:
    def __init__(self, settings: Settings, provider_override=None):
        self.settings = settings
        self.override = provider_override
        self.active = 0
        self.calls: deque[float] = deque()
        self.providers = {}
        self.mock = MockProvider()

    @asynccontextmanager
    async def admit(self):
        # All checks and reservation run without awaiting on this worker's event loop.
        if self.active >= self.settings.ai_max_concurrent_requests:
            raise ProviderError('server_busy', '分析服务正在处理其他请求，请稍后手动重试', 503,
                                {'Retry-After': '1'})
        now = time.monotonic()
        while self.calls and self.calls[0] <= now - 60:
            self.calls.popleft()
        if len(self.calls) >= self.settings.requests_per_minute:
            retry = max(1, math.ceil(60 - (now - self.calls[0])))
            raise ProviderError('rate_limited', '分析请求过于频繁，请稍后手动重试', 429,
                                {'Retry-After': str(retry)})
        self.calls.append(now)
        self.active += 1
        try:
            yield
        finally:
            self.active -= 1

    def provider(self, photo=False):
        if self.override is not None:
            return self.override
        if self.settings.provider == 'mock':
            return self.mock
        if photo not in self.providers:
            cls = DeepSeekProvider if self.settings.provider == 'deepseek' else OpenAIProvider
            # Configuration failures remain explicit and aren't cached as Mock results.
            self.providers[photo] = cls(self.settings, photo=photo)
        return self.providers[photo]

    async def close(self):
        providers, self.providers = self.providers, {}
        try:
            # Always try to release both role-specific pools, even if one close fails.
            results = await asyncio.gather(*(provider.close() for provider in providers.values()), return_exceptions=True)
            if any(isinstance(result, BaseException) for result in results):
                raise RuntimeError('Failed to close backend model connections') from None
        finally:
            self.calls.clear()
