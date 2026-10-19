# 后端运行与排查

后端只分析主动提交的照片和训练条件，返回草稿；不保存个人历史或分析结果。2026-10-19这一轮升级请求可靠性和诊断，未部署云服务。更换代码后必须重启后端，新行为才会生效。

## 启动

```sh
backend/.venv/bin/python -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000 --workers 1 --no-access-log
```

此命令读取已有 `backend/.env`，不会更改供应商、Key或SERVICE_TOKEN。`bootstrap_backend.py`只创建不存在的文件，不能用来覆盖用户配置。手机连接Mac时，需按README选择Mac实际局域网接口并重启监听；手机的localhost指向手机自身。正式使用HTTPS。

当前限流与并发计数保存在单个worker内存中，**只支持单worker的全局限额**。重启会清空窗口；多个实例不会共享额度，不应把单实例限制当作集群限制。

## 请求与模型连接

照片和训练各自按需创建一个模型客户端，后续请求复用，服务关闭时统一释放。状态查询不创建模型客户端，也不调用上游。依据[FastAPI lifespan](https://fastapi.tiangolo.com/advanced/events/)管理资源，利用[异步HTTP客户端的连接池](https://www.python-httpx.org/async/)复用连接；没有加入照片或模型结果缓存。

在 `.env` 中可选设置，未填写时使用以下默认值：

```dotenv
AI_MAX_CONCURRENT_REQUESTS=2
REQUESTS_PER_MINUTE=20
REQUEST_BODY_TIMEOUT_SECONDS=15
```

- 照片分析和训练生成共享并发限额；忙时立即返回503，不排队、不自动重试。健康和状态接口仍可查询。
- 有效认证的AI POST尝试计入一分钟滚动窗口，包括格式不合格的尝试；因并发已满而拒绝的请求不占该窗口。无效凭据不消耗AI限额，也不读取上传内容。
- 上传总时限默认15秒；照片完整请求最多 `MAX_IMAGE_BYTES + 256 KiB`，图片本身仍受MAX_IMAGE_BYTES限制，其他写入请求体最多64 KiB。实际收到的字节也会计数，不能只靠Content-Length绕过。
- 模型调用另受 `AI_TIMEOUT_SECONDS`和输出token上限约束，SDK重试仍为0。默认45秒模型超时配合当前iOS请求超时使用。
- 成功、错误、上传断开和ASGI任务取消都释放请求槽位。本轮未验证手机上传完成后断开网络会立即取消上游生成，不能据此保证取消后不计费；没有加入请求幂等或结果缓存。

## 连接诊断：不会调用模型

```sh
backend/.venv/bin/python scripts/check_backend.py
```

默认检查 `http://127.0.0.1:8000`；指定其他服务时：

```sh
backend/.venv/bin/python scripts/check_backend.py --url https://your-backend.example
```

脚本先GET `/health`，再使用本机SERVICE_TOKEN请求 `/v1/status`，只输出连通、认证、模式、配置就绪状态和服务生成的请求编号。`actualAIValidated=false`表示这次检查没有实际生成；Mock必须按演示理解。旧后端缺少就绪字段时提示版本/配置待检查，不误报全部就绪。

诊断不会跟随重定向、不会把模型Key传到服务、不会打印服务原始响应或覆盖任何文件；连接不经过环境代理。HTTP仅支持与客户端一致的本地开发地址/私有IPv4；其他地址要求HTTPS。Mac检查通过仍不证明手机的本地网络权限、域名解析或设备互访正常。

## 错误与日志

所有HTTP响应带服务生成的 `X-Request-ID`，并设置 `Cache-Control: no-store`。输入的X-Request-ID不会作为日志编号直接采信。日志只包含请求编号、白名单路由、状态码和处理耗时；未知路由记录为other，不记录查询参数、令牌、照片、训练条件或上游异常正文。保持关闭Uvicorn访问日志，不开启SDK的请求正文调试日志。

| 状态/错误码 | 含义 | 处理 |
| --- | --- | --- |
| 401 unauthorized | SERVICE_TOKEN不正确或不是Bearer认证 | 核对App服务凭据，不能填模型Key |
| 408 upload_timeout | 请求体上传超时 | 保留照片，检查网络后手动重试 |
| 413 image_too_large / request_too_large | 图片或请求体超过限制 | 缩小图片或请求 |
| 422 invalid_request | 格式、日期、训练条件或文件字段无效 | 修改输入；错误不会回显输入正文 |
| 429 rate_limited | 超过每分钟尝试数 | 参考Retry-After秒数，稍后手动重试 |
| 503 server_busy | 同时处理数已满 | 参考Retry-After，等待已有分析结束 |
| 503 configuration_missing | 真实模型配置不完整 | 修改后端配置并重启；不会变为Mock |
| 500 internal_error | 未预期的服务错误 | 用X-Request-ID对应日志排查，不把完整敏感输入发到聊天 |

原有模型认证、限额、超时和结构校验错误保持明确返回。配置校验异常文本也隐藏输入值，避免无效模型地址中的凭据被启动错误打印；依据[Pydantic配置说明](https://docs.pydantic.dev/latest/api/config/#pydantic.config.ConfigDict.hide_input_in_errors)。

## Mock实际HTTP验收

对已经运行且明确为Mock的服务：

```sh
backend/.venv/bin/python scripts/smoke_backend.py --url http://127.0.0.1:8000 --no-write-fixtures
```

脚本会先检查模式，再上传合成JPEG并生成固定演示计划；真实模式会在生成前停止。`--no-write-fixtures`保留仓库契约样本；不加该参数沿用原行为，更新合成测试样本。此检查不证明真实模型或餐食质量。

下一阶段可部署稳定HTTPS服务，再分别验证真实模型连接复用、手机取消/重试与实际餐食流程；这些尚未由本轮完成。
