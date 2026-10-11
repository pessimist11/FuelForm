# FuelForm 开发进度与实际证据

日期：2026-10-11（Asia/Shanghai）。本次在空工作区从零实现，原生路线未改变。

## 首次实现时的环境（下方追加原生验证进展）

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

## 2026-10-11 追加：Xcode 原生验证

用户安装完整Xcode后，已通过界面打开工程，选用FuelForm scheme / iPhone 18 Pro；当前developer目录为 `/Applications/Xcode.app/Contents/Developer`。实际版本：Xcode27.0（27A266a）、Swift6.4、iOS27.0；模拟器ID `1948D3AD-24BE-442F-A75E-BF0C4E274B9B`。

- 首次原生构建发现FuelFormApp.init在抛错前已给不可变container赋值，catch又赋值。改为先完整加载AppStore，再一次性初始化属性；保留失败时不清空存储的行为。
- Debug/Release模拟器构建均 **BUILD SUCCEEDED**；22项原生XCTest **TEST SUCCEEDED**，其中19项领域/契约、2项SwiftData磁盘/照片引用、1项Keychain。
- 实际通过Xcode Run启动App，Device Hub中看到FuelForm今日页：没有确认记录、目标与消耗未知、四个入口、记一餐和训练空状态。
- 进入“我的”时发现Keychain -34018；检查显示原模拟器App缺少私有访问身份。新增SDK条件化的Simulator entitlement，采用AppIdentifierPrefix + BundleID，只允许自己的Keychain组；真机仍由用户真实Team注入，未填造假的生产Team。
- 新增Keychain回归案例使用UUID命名的隔离账号与合成字符串，验证读/写/更新/删除，不读取或覆盖用户服务令牌；正常模拟器签名下通过。
- XcodeGUI旧调试会话曾卡在重复运行状态；正常退出、重新打开项目后恢复Run。Device Hub自动化导航/读取出现noWindowsAvailable、timeout等错误，已看到首页但**没有确认完整的手动记餐/训练/资料页UI流程通过**，保留验收待办。

实际命令（不禁用模拟器签名）：

```sh
xcodebuild -project ios/FuelForm.xcodeproj -scheme FuelForm -configuration Debug -destination 'id=1948D3AD-24BE-442F-A75E-BF0C4E274B9B' -derivedDataPath /private/tmp/FuelFormDerivedData -resultBundlePath /private/tmp/FuelForm-native-tests-2.xcresult test
xcodebuild -project ios/FuelForm.xcodeproj -scheme FuelForm -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/FuelFormDerivedData build
```

本机临时证据：`/private/tmp/FuelForm-native-tests-2.log`、同名xcresult，以及 `/private/tmp/FuelForm-release-build-2.log`；不含真实模型调用。最初21项测试未覆盖Keychain，修复后22项通过。原先“缺Xcode、iOS编译/SwiftData集成未验证”的历史限制已由这些结果部分解除；iOS17运行时、全UI流程、实际App重启、真实AI与iPhone仍未验证。变更目前保存在本地，尚未提交推送本次修复。

## 2026-10-12 追加：手动流程与实际 App 重启验收

在同一iPhone 18 Pro / iOS27模拟器通过Device Hub界面执行以下操作，使用标记为验收/QA的合成记录，不填写真实身体资料，不调用AI服务。

- 首页补上目标设置/调整、查看记录与草稿、建立/管理训练计划入口。保留四个底部标签页；空状态现在可以直接采取下一步操作。
- 「我的」正常打开，没有此前的Keychain -34018弹窗。保存临时目标1800/消耗2200，首页显示对应快照；此前11日的目标与消耗仍为空。
- 11日23:58录入300 kcal整餐草稿。午夜后首页自动显示12日，草稿仍属于11日；饮食历史显示草稿未计入。重新打开并确认后，11日显示300 kcal，12日不受影响。
- 12日录入并确认400 kcal：摄入400、剩余1400、估算缺口1800。编辑同一餐次为600后：摄入600、剩余1200、估算缺口1600；列表保持一条当天记录。
- 建立七天QA手动计划，今天徒手深蹲1组，其余休息日。开始后填写实际10次、勾选该组完成、动作标为完成并结束；界面显示已保存和结束时间。切到明天显示休息日，无完成任务。
- 使用Xcode Stop终止实际App进程，再Run启动：餐次600、目标1800/2200，以及训练的10次、完成状态、结束时间均保留；首页继续入口打开已有日志，不创建新日志。
- 收尾通过资料界面清空临时目标/消耗，并明确更新今日快照；首页恢复目标与消耗未知。停用QA计划后，当日无安排，已完成训练历史仍在。保留有验收/QA标记的餐次和历史，不将其打包到源码或Git。

最终代码的实际验证：

```sh
xcodebuild -project ios/FuelForm.xcodeproj -scheme FuelForm -configuration Debug -destination 'id=1948D3AD-24BE-442F-A75E-BF0C4E274B9B' -derivedDataPath /private/tmp/FuelFormDerivedData -resultBundlePath /private/tmp/FuelForm-final-tests-20261012.xcresult test
xcodebuild -project ios/FuelForm.xcodeproj -scheme FuelForm -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/FuelFormDerivedData build
```

结果：22项XCTest、0失败、TEST SUCCEEDED；Release BUILD SUCCEEDED；工程引用/配置/Swift语法检查和git diff --check通过。证据位于 `/private/tmp/FuelForm-final-tests-20261012.log`、同名xcresult及 `/private/tmp/FuelForm-final-release-20261012.log`。XcodeGUI最终Run也成功。

Device Hub的坐标点击持续报noWindowsAvailable，部分AX字段/Stepper在值变化后需要完整刷新，模拟器粘贴有异步剪贴板问题。改用界面可访问性按钮、直接键入数字/ASCII标记和系统返回快捷键完成以上流程；没有换用未授权的UI控制方式。首页入口让实际首次使用步骤也更直接。本次不把底部标签栏触摸、照片、删除、负数、大字号/深色/VoiceOver或全流程称为已通过。

当前devicectl设备列表只检测到iPhone 18 Pro模拟器（hardwareProperties.reality=simulated，transportType=sameMachine），未检测到真机。工程未配置个人Team；真机连接、账户与签名、照片/权限/网络及真实AI仍待完成。代码修复和验收文档将正常提交并推送现有main；推送结果以Git远端核验为准。
