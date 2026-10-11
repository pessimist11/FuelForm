# FuelForm

个人 iPhone 饮食与训练记录 App，Swift / SwiftUI / SwiftData，最低 iOS 17。四个入口：今日、饮食、训练、我的。个人历史只存手机，后端只做食物分析与计划草稿。

**当前状态：已使用 Xcode 27.0 / iOS 27.0 完成 Debug、Release 模拟器构建，22 项原生 XCTest 全部通过。已通过界面验证目标保存、手动餐次草稿/确认/修改、热量汇总、一周计划/休息日、实际训练记录与 App 重启后的数据保留。首页可直接设置目标、查看草稿和管理计划。相册/AI、完整界面与辅助功能、iPhone 真机安装仍待验收。** 详见 [进度与证据](docs/progress.md) 和 [验收清单](docs/acceptance.md)。

## 当前版本

- 手动餐次、整餐总热量、八项官方营养库，供餐重量和食用比例，草稿确认/编辑/删除及历史日期浏览。
- 照片持久保存，拍照/系统相册选择，显式演示与后端分析，可编辑营养草稿、原始分析保留；已确认记录不会被自动覆盖。
- 每日目标/消耗快照、摄入/剩余额度/估算缺口，负值、未知日期和未记全状态分别处理。总消耗手动设置，计划训练不算已发生消耗。
- 手动/AI计划草稿、日期安排、周复制、多周、休息日、动作库与目标、实际逐组日志、替换/跳过及历史记录。
- 资料、体重图表、离线手动记餐/训练、Keychain服务凭据、带版本JSON导出。**导出不含照片，不是完整备份，暂不支持恢复。**

## 后端快速开始（先跑 Mock，无需模型 Key）

在项目根目录操作。推荐 Python 3.13（实际使用3.13.15；代码要求3.11+）。

```sh
python3.13 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.lock
python3 scripts/bootstrap_backend.py
backend/.venv/bin/python -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000 --no-access-log
```

本工作区已创建 `backend/.venv`、安装依赖并生成被忽略的 `backend/.env`。bootstrap 只创建一次，包含显式Mock模式与随机访问令牌，不输出令牌、不覆盖既有配置。手动复制 `.env.example` 时必须替换 SERVICE_TOKEN。所有分析/目录接口需要 Bearer 认证，健康接口不需。

在本机编辑 `backend/.env`，把 **SERVICE_TOKEN** 填入 iPhone「我的 → 分析服务」，点击保存到Keychain。不要把模型Key填到App。服务连接检查只证明后端可达和当前模式，不能证明模型能调用。

实际HTTP联调（先保持Mock后端运行，另一终端执行）：

```sh
backend/.venv/bin/python scripts/smoke_backend.py
```

脚本使用合成图片和条件，不输出令牌；只在显式Mock模式运行，更新 `ios/Tests/Fixtures`。固定示例与图片内容无关，不应当作识别准确性证据。演示餐次独立分区且不计入个人摄入；演示计划禁止直接启用。只有手动核对并明确转为个人草稿后才能确认用于个人记录。App也有明确标注的本地演示按钮，可在未配置服务时编辑与确认流程。

## 真实 AI

在后端 `.env` 设置并重启服务：

```dotenv
PROVIDER=openai
SERVICE_TOKEN=<自己的服务访问令牌>
OPENAI_API_KEY=<自己的模型API Key>
OPENAI_MODEL=gpt-4.1-mini
OPENAI_BASE_URL=https://api.openai.com/v1
AI_TIMEOUT_SECONDS=45
```

模型可替换为API账户可访问、支持图片输入和结构化输出的模型。此示例的能力已查阅[官方能力页](https://developers.openai.com/api/docs/models/gpt-4.1-mini)；不保证账户可用性或实际效果。适配器使用官方 Responses API/Pydantic结构化输出，`store=False`，SDK自动重试0。当前没有配置真实Key，也没有做付费调用。配置缺失/超时/失败明确报错，不会回退Mock。更多官方引用及隐私边界见 [架构](docs/architecture.md)。

## iOS 工程与模拟器

已生成 `ios/FuelForm.xcodeproj`、共享FuelForm scheme、App/XCTest targets、资源和两种Info.plist。无第三方iOS依赖。无需XcodeGen。

1. 安装兼容当前macOS且包含iOS 17+ SDK的**完整Xcode**及一个iPhone模拟器运行时。本工作区所在 Mac 已安装 Xcode 27.0 和 iOS 27.0；其他机器仍需安装这些组件。
2. 必要时切换工具目录并在Xcode中完成首次启动设置：

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun simctl list devices available
open ios/FuelForm.xcodeproj
```

3. 选择FuelForm scheme和可用iPhone模拟器，Run。先测试离线手动流程；再在服务配置填 `http://localhost:8000` 和SERVICE_TOKEN，保存凭据后做Mock分析。模拟器相机不可用时有说明，可从相册选择。
4. Cmd-U 执行核心、SwiftData与Keychain测试，按 [验收清单](docs/acceptance.md) 走UI。本次已通过 `xcodebuild test` 执行22项测试；实际Xcode/SDK版本和剩余UI项目见进度文档。

可重复生成工程：

```sh
python3 scripts/generate_xcode.py
# 若已设定个人签名，重生成时带上你真实的Bundle ID和Team ID：
python3 scripts/generate_xcode.py --bundle-id <自己的BundleID> --team-id <自己的TeamID>
```

生成器会覆盖pbxproj、scheme和Info.plist；新增源码/测试后重跑。不要不带参数重新覆盖你手工配置的签名。默认Bundle ID `personal.FuelForm` 仅为本地开发占位，请为真机选择自己的唯一ID。

模拟器构建使用专用 `FuelForm-Simulator.entitlements`，只给本 App 的私有 Keychain 身份；真机构建由真实 Team/Provisioning Profile提供身份。请保持默认模拟器签名设置，不用 `CODE_SIGNING_ALLOWED=NO` 运行需要Keychain的验收。参见 [Apple访问组说明](https://developer.apple.com/documentation/Security/sharing-access-to-keychain-items-among-a-collection-of-apps)。

## 安装到自己的 iPhone

需要iOS17+设备、完整Xcode、USB或已配对无线调试。按照 [Apple运行与签名说明](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)：在Xcode登录自己的Apple Account，给FuelForm/App与测试target选择Team，开启自动签名，连接并信任iPhone，选择设备后Run。按 [Apple Developer Mode说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device/) 在iPhone「隐私与安全」开启开发者模式并完成设备重启确认。个人开发签名可能需要重新签名，具体限制以Xcode账户为准；无需先上架App Store。

模拟器的localhost是Mac，**真机的localhost是iPhone**。在可信同Wi-Fi环境启动：

```sh
backend/.venv/bin/python -m uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port 8000 --no-access-log
scutil --get LocalHostName
```

将命令实际返回的主机名拼为 `http://<主机名>.local:8000`，填入App；不要照抄示例主机名。允许macOS防火墙入站和iPhone本地网络访问。Debug只放开本地网络ATS，并在客户端限制localhost/127.0.0.1/.local；HTTP局域网请求未加密，仅用于可信本地开发。Release完全使用HTTPS和系统信任证书。没有对整个App放开任意HTTP。

设备安装、相机、真实HEIC/方向、本地网络权限、锁屏重启数据、动态文字/深色/VoiceOver以及文件分享都需真机清单逐项验证。删除App会删除本地记录，当前JSON不含照片且不能恢复，升级测试前另行保留App容器。

## 验证入口

```sh
./scripts/verify.sh
```

运行工程/资源/传输配置/Swift语法结构检查、后端pytest、Foundation Swift业务与契约检查。当前实际通过后端33项、Swift19项（含实际HTTP产生的响应样本解码）。这个命令**不运行iOS模拟器**。CLT缺少XCTest，Swift检查采用自带断言可执行入口；相同案例在Xcode中由XCTest执行。

以下原生构建/测试入口已经在 Xcode 27 上执行通过，设备ID从你实际的simctl输出选择：

```sh
xcodebuild -project ios/FuelForm.xcodeproj -scheme FuelForm -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
xcodebuild -project ios/FuelForm.xcodeproj -scheme FuelForm -configuration Debug -destination 'id=<实际模拟器UDID>' test
xcodebuild -project ios/FuelForm.xcodeproj -scheme FuelForm -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

## 实际使用的环境

| 工具 | 本次版本/状态 |
| --- | --- |
| Swift | 6.4，arm64 macOS，工程使用Swift5语言模式 |
| Python | 3.13.15；系统python3为3.9.6，不用于后端 |
| uv | 0.12.17 |
| FastAPI / Pydantic | 0.143.0 / 2.14.0 |
| Uvicorn / OpenAI SDK | 0.54.0 / 3.28.0 |
| Pillow / pillow-heif | 12.3.0 / 1.8.1 |
| pytest | 9.1.1 |
| Xcode / iOS SDK / simulator | Xcode 27.0（27A266a）、iOS 27.0、iPhone 18 Pro（模拟器） |

直接依赖在 `backend/requirements.txt`，完整已安装版本在 `backend/requirements.lock`；含SOCKS代理需要的socksio。`.gitignore` 排除凭据、构建产物、个人数据与照片。项目从空工作区开始开发，源码仓库为 [pessimist11/FuelForm](https://github.com/pessimist11/FuelForm)，默认分支为 `main`。

## 后续优先级

继续完成模拟器完整流程和真机验收；再用真实照片核对AI与人工值。之后优先完整照片备份/恢复和迁移演练，再扩充有来源的本地食物库。详见 [产品范围](docs/product.md)、[数据模型](docs/data-model.md)、[营养来源](docs/nutrition.md)。
