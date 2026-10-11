# 架构与接口

## 本机与后端边界

SwiftUI 四个入口 → AppStore → SwiftData 版本化记录。Foundation 核心模块只含值模型、校验与计算，可单独在 macOS 执行。照片落 Application Support/Photos，UUID 文件名；数据只保存相对路径。所有个人资料、体重、餐次、快照、计划和实际日志只在手机。无自动演示数据导入。

URLSession 使用 ephemeral session，不建立持久请求缓存；必要的服务访问令牌放 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain。模型 API Key 不进入 iOS。

FastAPI 通过 Provider 协议调用 MockProvider 或 OpenAIProvider。`PROVIDER` 决定模式，不按调用失败自动降级。后端没有个人数据库，原图仅短暂处理，图片归一化后发送模型。多部分上传框架可能在请求期间使用临时文件；请求结束关闭上传文件，不做长期保存。部署时保持一个 worker（当前限流器是单进程）。不记录图片或完整请求。启动命令关闭 access log。

## HTTP 契约 v1

除 `/health` 外需要 `Authorization: Bearer <SERVICE_TOKEN>`。所有字段使用 camelCase，来源包含 kind/label/version/reference。

| 方法/路径 | 请求 | 响应/目的 |
| --- | --- | --- |
| GET /health | 无 | 最小存活状态，不证明 AI 可用 |
| GET /v1/status | 认证 | mode、catalogVersion，不暴露 Key |
| GET /v1/foods | 认证 | 带版本及来源的食物库 |
| GET /v1/exercises | 认证 | 动作库 |
| POST /v1/analyze | multipart，字段 image | mode、isFood、可编辑 items、questions、assumptions、warnings |
| POST /v1/plans/draft | startDate、weeks、trainingDays、durationMinutes、equipment、experience、goal、avoidExerciseIds | mode、draft、warnings |

分析 food item：供餐重量 servedGrams；basis=per100 时营养值每100g，basis=total 时营养值是整份供餐。后端不扣除剩余量。食物 ID 与烹饪方式同时匹配目录才使用数据库；否则标记 AI/演示估算。没有模型自报准确率或误差区间。

图片：最大原请求图像 8 MiB，整体请求上限附加 256 KiB；校验真实解码/格式/像素数，支持 JPEG/PNG/HEIC/WebP，EXIF 方向修正、移除元数据、最长边1600px。iOS 先将相册 HEIC 等转为正向 JPEG，再上传。相册缩略图生成允许读取40MiB内原图，不先完整解码大型原图。

计划：连续日期、每天结构、每周训练天数、动作库、器械、避开动作、组数、次数、重量与休息时间校验；粗略用每次3秒+组间休息+热身5分钟检查是否能放进请求时长。这只是草稿校验，**不是运动热量估算**。

错误分开报告 unauthorized、configuration_missing、invalid_image、image_too_large、ai_timeout、ai_request_failed、invalid_ai_output、invalid_plan、rate_limited。请求默认45秒AI超时；客户端65秒单请求、70秒资源超时；SDK重试为0。UI有取消及手动重试，没有无限重试。

## 真实适配器官方核实（2026-10-11）

已读取 [OpenAI 图像输入](https://developers.openai.com/api/docs/guides/images-vision)、[结构化输出](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)、[Python SDK](https://developers.openai.com/api/reference/python) 与 [GPT-4.1 mini 能力页](https://developers.openai.com/api/docs/models/gpt-4.1-mini)。后者列出图片输入、Responses 端点及结构化输出支持。

实现用 `AsyncOpenAI.responses.parse(..., text_format=PydanticModel, store=False)`；安装 SDK 3.28.0 的方法签名和 `max_retries=0` 已实际检查。默认运行 Mock；真实模式必须显式设置 Key 和模型名。`.env.example` 的 `gpt-4.1-mini` 是官方已核实能力的可配置示例，与编写代码的模型无关。是否在用户 API 账户可用、费用与真实质量尚未验证。

`store=False` 表示不保存为可检索 Response；不等于保证供应商零保留。供应商数据策略由实际账户与官方政策决定。本项目后端自身不长期存照片。

## 开发网络

Debug Info.plist 只有 `NSAllowsLocalNetworking`，APIClient 只允许 http://localhost、127.0.0.1 或 `.local` 主机。Release 没有 ATS 例外且只接受 HTTPS。没有全局 `NSAllowsArbitraryLoads`。真机不能使用 localhost 连 Mac，使用同 Wi-Fi Mac 的 `.local` 主机名；HTTPS 可使用 IP/域名及系统信任证书。iOS 的本地网络权限拒绝时请求报错，手动功能不受影响。

## Xcode 27 模拟器签名

原生验证发现无私有身份的模拟器App会返回Keychain -34018。工程仅在iphonesimulator SDK配置 `FuelForm-Simulator.entitlements`，使用 `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` 作为私有身份与唯一访问组；iphoneos不使用该文件，由真实签名Team/Provisioning Profile注入。没有扩大到其他App的Keychain组。采用正常签名后，隔离Keychain测试通过；[Apple访问组与AppID说明](https://developer.apple.com/documentation/Security/sharing-access-to-keychain-items-among-a-collection-of-apps)。
