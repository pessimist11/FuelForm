# FuelForm 开发进度与实际证据

日期：2026-10-11（Asia/Shanghai）。本次在空工作区从零实现，原生路线未改变。

## 环境

- 当前 `xcode-select -p` 为 `/Library/Developer/CommandLineTools`。
- `xcodebuild -version` 失败：requires Xcode；`xcrun --sdk iphoneos --show-sdk-version` 找不到iOS SDK；`xcrun simctl` 无工具。/Applications中没有Xcode。
- Swift 6.4与macOS SDK可用。系统Python3.9.6，实际后端使用本机uv已有的Python3.13.15。uv0.12.17。
- 没有XcodeGen；用Python标准库生成工程。初始无AGENTS/源码/Git仓库。
- 无真实模型Key；当前 `.env` 为显式Mock及本地随机服务令牌（不打印、不入版本库）。

## 分阶段结果

| 阶段 | 已完成实现和验证 | 仍待验证 |
| --- | --- | --- |
| 一：基础 | 目录、Swift原生工程、共享scheme、两targets、资源、FastAPI认证配置；后端实际启动；核心模块实际编译执行；工程文件格式和引用检查 | 最小iOS编译（缺完整Xcode/SDK） |
| 二：本地记录 | 资料/体重、餐次多项目/草稿/总热量/补录、计算/每日快照、计划编辑/多周复制、实际逐组日志、SwiftData版本化存储；业务检查通过 | SwiftUI/SwiftData的iOS类型检查、磁盘重启与离线UI |
| 三：照片/草稿 | 相册、相机权限、持久JPEG、取消/错误/重试、可编辑草稿、明确本地/后端Mock、AI条件表单与确认启用；Mock后端HTTP和Swift DTO验证 | iOS相册/相机/确认UI实际流程 |
| 四：真实适配 | 官方资料核实；OpenAI Responses/Pydantic适配、配置模型/地址、store=false、0自动重试、营养来源/生熟匹配；SDK替身、超时/异常测试 | 无真实Key，未实际调用AI；未做iOS URLSession端到端 |
| 五：收尾 | Keychain、离线手动路径、文件引用删除、孤儿文件清理、版本化导出分享、中文错误/空状态、深浅色/动态字号实现、文档/AGENTS/安装及验收入口 | iOS编译/界面/设备/分享/真实照片；完整备份与恢复列后续 |

各阶段不表示已达到完整真机验收。当前交付具备主要业务实现及可运行后端；需完整Xcode完成最后的原生编译与设备验证后，才能确认可日常使用的iPhone MVP。

## 实际运行的验证

1. `python3 scripts/generate_xcode.py` 成功，生成pbxproj、scheme、Debug/Release Info.plist。`plutil -lint`通过。`scripts/check_project.py`检查文件与对象引用、targets/资源、ATS、scheme XML和Swift语法；通过。这些**不是xcodebuild**。
2. `backend/.venv/bin/python -m pytest backend/tests -q`：**33 passed**。覆盖认证、启动凭据、Mock标签、图片格式/大小/方向/PNG/HEIC、生熟匹配、非食物替身、真实配置缺失、训练日1–6/器械/避开/输入结构/异常计划/时长、限流、真实适配参数/超时/拒绝与目录一致。
3. `swift run --disable-sandbox ... FuelFormCoreChecks`：**19项通过**。Core模块实际编译运行：确认/草稿/编辑/删除、重量比例、两种热量计算、未知/未记全、历史快照、跨午夜/闰日/DST、计划日志隔离/去重/休息/复制/冲突/未来日期、重排日志独立、原始分析/JSON与3项后端响应契约。
4. 实际启动Uvicorn（本机127.0.0.1:8000，无access log），运行 `scripts/smoke_backend.py`：认证状态、合成JPEG multipart Mock分析、两周训练草稿均通过；合成响应保存到 `ios/Tests/Fixtures`并被Swift解码。验证后停止服务，运行方式在README。这**不是iOS界面或真实AI联调**。
5. 实际安装并检查OpenAI SDK3.28.0：`responses.parse`签名含text_format、store，max_retries=0。替身请求验证图片data URL与配置模型。不持有真实Key、不产生模型调用费用。
6. USDA官方SR Legacy CSV压缩包实际下载、读取、提取8项营养值，记录来源链接/版本/压缩包SHA256，前后端一致。

## 遇到的限制与修复

- 沙箱内下载依赖与绑定本机端口最初受限，经授权环境的自动审批后成功执行。没有遗留自动审批拒绝项。
- `swift test`不能加载XCTest，CLT不含该框架。改用同一案例的Foundation断言执行入口；Xcode工程保留XCTest测试。SwiftPM的缓存写入和manifest子沙箱受限，使用临时缓存与disable-sandbox；没有安装新Swift工具链。
- SwiftData macOS类型检查尝试失败：CLT缺少SwiftDataMacros插件，无法证实持久化编译；没有伪装为通过。
- 实际SDK初始化发现本机SOCKS代理需要socksio，已添加依赖并验证。超大multipart最初得到泛化400，改为在解析前限流式读取请求大小并明确返回413，测试通过。
- 食物响应保留模型原始结构化候选及营养匹配结果；演示餐次独立分区且不计入个人统计，演示计划必须明确转为个人草稿才可启用。
- 新增安排日期变更回归：按照安排ID+日期查日志，避免调整日期后错误复用过去训练；稀疏周复制补齐休息日。

## 未执行或未证实

- iOS Debug/Release构建、XCTest集成测试、SwiftData磁盘重启、真实App离线操作。
- 任何模拟器UI、浅深色/辅助功能/小屏/动态字号视觉检查。
- iPhone签名安装、相机/相册权限、真实HEIC及方向、本地网络/HTTPS、锁屏Keychain和分享。
- 真实AI食物/训练模型调用、质量、实际账号可用性或成本。
- 真正旧版本的迁移、照片完整备份/恢复。

后续需要：完整Xcode及模拟器；自己的Apple Account与iPhone设备操作；若使用真实AI，在后端私下填写API Key及可访问模型。不要把凭据发进聊天。具体步骤与判断标准见README和acceptance.md。
