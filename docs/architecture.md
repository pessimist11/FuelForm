# 架构与接口

## 本机与后端边界

SwiftUI 四个入口 → AppStore → SwiftData 版本化记录。Foundation 核心模块只含值模型、校验与计算，可单独在 macOS 执行。照片落 Application Support/Photos，UUID 文件名；数据只保存相对路径。所有个人资料、体重、餐次、快照、计划和实际日志只在手机。无自动演示数据导入。

URLSession 使用 ephemeral session，不建立持久请求缓存；必要的服务访问令牌放 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain。模型 API Key 不进入 iOS。

FastAPI 通过 Provider 协议调用 MockProvider、OpenAIProvider 或 DeepSeekProvider。`PROVIDER` 决定模式，不按调用失败自动降级。后端没有个人数据库，原图仅短暂处理，图片归一化后发送模型。多部分上传框架可能在请求期间使用临时文件；请求结束关闭上传文件，不做长期保存。部署时保持一个 worker（当前限流器是单进程）。不记录图片或完整请求。启动命令关闭 access log。

## HTTP 契约 v1

除 `/health` 外的v1接口需要 `Authorization: Bearer <SERVICE_TOKEN>`。认证在读取上传内容和解析请求体之前完成。所有字段使用 camelCase，来源包含 kind/label/version/reference。

| 方法/路径 | 请求 | 响应/目的 |
| --- | --- | --- |
| GET /health | 无 | 最小存活状态，不证明 AI 可用 |
| GET /v1/status | 认证 | mode、catalogVersion、模型配置就绪与limits，不暴露 Key |
| GET /v1/foods | 认证 | 带版本及来源的食物库 |
| GET /v1/exercises | 认证 | 动作库 |
| POST /v1/analyze | multipart，字段 image | mode、isFood、可编辑 items、questions、assumptions、warnings |
| POST /v1/plans/draft | startDate、weeks、trainingDays、durationMinutes、equipment、experience、goal、avoidExerciseIds | mode、draft、warnings |

分析 food item：供餐重量 servedGrams；basis=per100 时营养值每100g，basis=total 时营养值是整份供餐。后端不扣除剩余量。食物 ID 与烹饪方式同时匹配目录才使用数据库；否则标记 AI/演示估算。没有模型自报准确率或误差区间。

图片：最大原请求图像 8 MiB，整体请求上限附加 256 KiB；校验真实解码/格式/像素数，支持 JPEG/PNG/HEIC/WebP，EXIF 方向修正、移除元数据、最长边1600px。iOS 先将相册 HEIC 等转为正向 JPEG，再上传。相册缩略图生成允许读取40MiB内原图，不先完整解码大型原图。

计划：连续日期、每天结构、每周训练天数、动作库、器械、避开动作、组数、次数、重量与休息时间校验；粗略用每次3秒+组间休息+热身5分钟检查是否能放进请求时长。这只是草稿校验，**不是运动热量估算**。

错误分开报告 unauthorized、configuration_missing、invalid_image、image_too_large、ai_timeout、ai_request_failed、invalid_ai_output、invalid_plan、rate_limited。请求默认45秒AI超时；客户端65秒单请求、70秒资源超时；SDK重试为0。UI有取消及手动重试，没有无限重试。

2026-10-19增加RequestGuard与BackendRuntime：单worker内共享照片/计划准入，默认2个并发、20次/分钟，忙时503且不排队，429/503带Retry-After。总上传时限15秒，图片请求按原大小加256KiB multipart开销，其他写入最多64KiB；同时检查声明和实际字节。只记录服务生成请求ID、固定路由、状态及耗时。Validation错误不回显输入，未预期异常返回安全500。模型客户端按照片/计划角色延迟创建并复用，在lifespan结束时释放；不保存或缓存照片/分析结果。详细语义和限制见[运行说明](backend-operations.md)。

## 真实适配器官方核实（2026-10-11）

已读取 [OpenAI 图像输入](https://developers.openai.com/api/docs/guides/images-vision)、[结构化输出](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)、[Python SDK](https://developers.openai.com/api/reference/python) 与 [GPT-4.1 mini 能力页](https://developers.openai.com/api/docs/models/gpt-4.1-mini)。后者列出图片输入、Responses 端点及结构化输出支持。

实现用 `AsyncOpenAI.responses.parse(..., text_format=PydanticModel, store=False)`；安装 SDK 3.28.0 的方法签名和 `max_retries=0` 已实际检查。默认运行 Mock；真实模式必须显式设置 Key 和模型名。`.env.example` 的 `gpt-4.1-mini` 是官方已核实能力的可配置示例，与编写代码的模型无关。是否在用户 API 账户可用、费用与真实质量尚未验证。

`store=False` 表示不保存为可检索 Response；不等于保证供应商零保留。供应商数据策略由实际账户与官方政策决定。本项目后端自身不长期存照片。

## 开发网络

Debug Info.plist 使用 `NSAllowsLocalNetworking`，并为127.0.0.1及私有IPv4范围10/8、172.16/12、192.168/16添加ATS例外，APIClient同步限制为localhost、127.0.0.1、`.local`及这些私有IPv4。Release没有ATS例外且只接受HTTPS；没有全局 `NSAllowsArbitraryLoads`。真机不能使用localhost连Mac；同Wi-Fi的 `.local` 主机名无法解析时，可用Mac局域网IPv4直接连接。HTTPS可使用IP/域名及系统信任证书。URLSession等待首次本地网络授权，仍受70秒资源超时约束；错误提示区分主机名解析和主机连接失败，手动功能不受影响。

## Xcode 27 模拟器签名

原生验证发现无私有身份的模拟器App会返回Keychain -34018。工程仅在iphonesimulator SDK配置 `FuelForm-Simulator.entitlements`，使用 `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` 作为私有身份与唯一访问组；iphoneos不使用该文件，由真实签名Team/Provisioning Profile注入。没有扩大到其他App的Keychain组。采用正常签名后，隔离Keychain测试通过；[Apple访问组与AppID说明](https://developer.apple.com/documentation/Security/sharing-access-to-keychain-items-among-a-collection-of-apps)。


## DeepSeek接入（2026-10-13）

按用户选择新增显式 `PROVIDER=deepseek`，独立Key、服务地址、训练与照片模型配置。真实适配器共享Responses请求/解析与错误处理；DeepSeek保留独立供应商身份，客户端和后端契约允许 `deepseek`，不能误判为Mock。原始供应商响应仍保存在用户确认值之外。

本轮实际读取 [DeepSeek Vision](https://api-docs.deepseek.com/guides/vision/)、[Responses兼容说明](https://api-docs.deepseek.com/guides/responses_api/) 和 [Models API](https://api-docs.deepseek.com/api/list-models/)。目前官方文档列出 `deepseek-flash` 支持图片，而Pro为文字输入。使用官方HTTPS端点、内联归一化JPEG和结构化输出。请求关闭额外思考，显式限制输出与超时、SDK重试0；不发送不支持的store参数。文档所述无状态API不等于所有供应商数据处理层都保证零保留。

`/v1/status`认证后返回供应商、照片/训练模型、配置就绪标志及缺项，不返回Key。就绪标志只检查配置，不验证Key、余额、账户权限或实际生成。原字段仍在，新字段可被旧客户端忽略；新客户端兼容旧状态响应。文字模型无法直接用于照片，配置不符时在调用上游之前拒绝。401/403/429/模型不可用/输入拒绝等上游错误转成可操作的安全文案，不透传上游正文。

诊断 `scripts/check_ai.py`默认只检查本机配置；`--models`显式读取账户模型列表；`--live`最多发起一周训练草稿与纯色非食物图片两次生成。没有Key时只能完成替身、实际localhost错误路径和客户端契约验证，不能称为真实AI已接通。
