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

## 2026-10-12 追加：真机签名与安装

- 后续连接 iPhone 15 Pro（iOS 26.7.1），用户开启开发者模式、登录 Xcode 并解锁设备；明确授权向个人开发 Team 注册设备、签名并安装。
- 工程本地配置真实个人 Team，Bundle ID 为 `com.pessimist11.FuelForm`。真机 Debug 签名构建成功；签名校验通过，开发描述文件包含当前设备，有效期至 2026-10-19。个人签名配置在后续第一轮升级提交中一并保存；证书、描述文件及私钥不纳入版本库。
- `devicectl device install app` 返回 success，FuelForm 已安装。模拟器 QA 数据未迁入手机。
- 首次启动被 iOS 安全检查拒绝。用户在手机上完成开发者信任后，再次 `devicectl device process launch` 返回 success；随后仅查询 FuelForm 进程，确认进程仍在运行。真机安装和启动已验证，尚未完成真机界面及业务全流程验收。
- 本机证据：`/private/tmp/FuelForm-device-build-registered.log`、`/private/tmp/FuelForm-install-result.json`、`/private/tmp/FuelForm-launch-result.json`、`/private/tmp/FuelForm-running-process.json`。真实 AI、照片与权限、网络及锁屏 Keychain 等真机验收仍待完成。


## 2026-10-12 追加：第一轮体验升级

本轮范围为今日页、记餐流程、固定确认区域与资料页键盘问题。保持现有SwiftData schema和领域计算，不进行数据重置；个人签名与Bundle ID保持现有配置。

- 今日页改为热量概览、早餐/午餐/晚餐/加餐卡片与今日训练。重点展示已记录摄入、剩余额度；未知值、超过目标、估算盈余仍有明确文案。计算解释按需展开。
- 新餐次提供拍照/相册、搜索食物、快速输入热量入口。名称、供餐重量、整份热量、食用比例直接在主页面编辑；营养来源及原始分析移入详情。
- 底部固定本餐合计、存草稿和确认按钮；有未保存修改时提醒保留或放弃，成功保存才清理未被引用的临时照片。照片加载和分析任务校验request ID，取消后的过期结果不能写入新编辑状态。
- 最大辅助字号下修正日期裁切和固定操作区过高问题；概览和数值行可转为纵向，日期控件与固定操作区限至可用的紧凑字号。
- 工作区BUG记录指出资料页键盘无法收起。资料、体重和服务字段接入FocusState；增加键盘“收起键盘”、滚动收起和导航栏保存入口。保存资料时结束输入；单日快照编辑页也补上键盘收起。

实际验证：最终22项XCTest、0失败；Debug/Release模拟器、真机Debug签名构建均成功。模拟器经界面验证草稿400不计入→确认400→修改600；1800/2200快照下余额1200、缺口1600；改2400后超额600、盈余200；实际停止/重启仍保留；删除后无记录显示未知。熟米饭200g吃75%显示150g/195kcal。关闭时放弃修改不会覆盖已保存值。合成资料180/75保存后重新打开保留，之后还原为空。后端未启动，以上手动流程可执行。浅深色及最大辅助字号检查已完成重点页面，软件键盘完整触摸/VoiceOver/小屏仍待，不能称全UI通过。

用户重新连接并解锁iPhone后，使用同一个Bundle ID覆盖安装升级版，安装返回success；启动返回success，随后FuelForm进程仍在运行。没有卸载App，没有改动手机个人记录，也没有把模拟器合成数据搬入手机。真机数据界面、拍照、权限、网络与真实AI的完整验收仍待。

证据位于本机临时目录：`/private/tmp/FuelForm-upgrade-final-tests.log`及同名xcresult、`/private/tmp/FuelForm-upgrade-final-release.log`、`/private/tmp/FuelForm-upgrade-final-device.log`、`/private/tmp/FuelForm-upgrade-install.json`、`/private/tmp/FuelForm-upgrade-launch.json`、`/private/tmp/FuelForm-upgrade-processes.json`。本轮代码、工程配置与验收文档纳入第一轮体验升级提交。用户的BUG记录文件保留，待手机触摸复核；推送结果以Git远端核验为准。


## 2026-10-13 追加：DeepSeek后端与真实API接入

用户选择DeepSeek。本轮实际读取官方Vision、Responses兼容说明和Models接口文档，核实 `deepseek-flash` 的图片输入与结构化响应能力。添加独立供应商配置、可分开的训练/照片模型；不沿用OpenAI Key，不把文字模型当作可识图模型。统一Responses适配器维持Pydantic校验、超时、输出上限和SDK重试0。DeepSeek关闭额外思考，不发送其不支持的store参数。

- 后端契约与iOS契约允许明确的 `deepseek` 模式。餐次仍需确认，训练仍保存为未启用草稿；演示隔离和历史快照规则保留。
- 状态接口在认证后报告供应商、模型、照片/训练配置就绪与缺项；App在服务配置区显示这些信息。就绪不等于已验证真实调用。
- 上游认证、访问拒绝、额度/限流、模型/接口不可用、输入拒绝、超时和异常结构返回具体安全文案；不转发上游正文，不自动切Mock。
- 新增 `scripts/check_ai.py`：默认只检查本机配置，`--models`读取账户模型列表，`--live`至多两次真实生成，只使用合成纯色非食物图片和通用一周训练条件，不输出Key或完整响应。
- 用户询问 `.env`位置，已核验 `/Users/saki/FuelForm/backend/.env`存在且被Git忽略。Finder默认隐藏点文件，⌘+Shift+.可显示。本机已选择DeepSeek，原SERVICE_TOKEN保留，Key只由用户在本机填写；示例配置和bootstrap不包含真实凭据。

实际验证：49项后端pytest通过（含实际SDK序列化/解析的MockTransport测试，不能把它称为真实AI）；20项Foundation检查通过；23项原生XCTest、0失败；Release模拟器与真机Debug签名构建成功。未填Key阶段实际运行localhost HTTP：状态正确显示DeepSeek缺Key，计划返回503配置错误，无演示回退。

用户随后填写Key，检查时两个模型都为准确名称 `deepseek-flash`。官方 `/models`请求通过，账户列表包含配置模型；随后实际执行 `scripts/check_ai.py --live`，一周7天训练草稿经日期/动作/器械/时长校验通过，合成非食物图片结构化请求通过且没有食物项目。总共两次真实生成，无自动重试。没有上传个人照片、身体资料或历史，没有把草稿写入手机或启用计划。重启本机后端后，实际HTTP状态返回DeepSeek、photoReady/planReady均true；该状态仍仅证明配置就绪。

本机证据：`/private/tmp/FuelForm-deepseek-tests-20261013.log`及同名xcresult、`/private/tmp/FuelForm-deepseek-release-20261013.log`、`/private/tmp/FuelForm-deepseek-device-20261013.log`、`/private/tmp/FuelForm-deepseek-core-20261013.log`。真实模型检查与调用结果记录在本轮工具输出，未保存完整模型响应。用户重新连接并解锁iPhone后，升级包签名校验通过，覆盖安装与启动均返回success，随后进程仍在运行。Mac后端仅绑定当前局域网接口并保持SERVICE_TOKEN认证，Mac .local地址的实际HTTP认证检查通过；已请用户在同Wi-Fi手机中自行填写服务地址和SERVICE_TOKEN并检查连接。手机网络/照片与实际餐食质量尚待验收，不能称完整手机AI流程已完成。

## 2026-10-13 追加：手机局域网连接排查

用户反馈无法连接服务、保存凭据似乎无反应。检查确认后端进程与监听正常；Mac通过主机名和IP的认证请求均返回200。用户在iPhone Safari实测 `/health`：IP返回ok，`.local`打不开。当前证据指向主机名解析路径受限，不能据此认定校园网完全隔离设备，也不能将网络错误归因于Keychain。

- Debug增加私有IPv4直连（10/8、172.16/12、192.168/16），客户端与ATS范围保持一致；Release仍只接受HTTPS。按当前Apple文档给iOS17+配置CIDR例外，未放开全局HTTP。
- 保存凭据时收起键盘，并将成功/清除提示放到按钮下方；原来位于页面底部的反馈容易被忽略。原生隔离账号Keychain读写、更新和删除测试通过，没有覆盖用户令牌。
- URLSession等待首次本地网络授权，区分域名解析失败、主机连接失败和其他网络错误；没有更改校园网、系统DNS或防火墙设置。
- 24项原生XCTest、0失败，Release模拟器及真机Debug构建、真机签名核验通过。模拟器通过真实界面输入私网IP和无效合成凭据，收到后端“服务访问凭据无效”，验证请求已穿过客户端地址校验、ATS和网络到达认证层；没有存储该测试凭据或调用模型。
- 用户重新连接后，同Bundle ID覆盖安装及启动均success，随后进程仍在运行；已请用户将手机服务地址改为当前Mac IPv4并重新保存凭据、检查状态。手机App认证连接及实际照片链路仍待用户验证。

证据：`/private/tmp/FuelForm-ip-tests-20261013.log`及同名xcresult、`/private/tmp/FuelForm-ip-device-20261013.log`、`/private/tmp/FuelForm-ip-release-20261013.log`、`/private/tmp/FuelForm-ip-install-20261013.json`、`/private/tmp/FuelForm-ip-launch-20261013.json`。没有新增真实模型调用。

用户随后在iPhone明确反馈“凭据已保存，后端已连接 · DeepSeek”。据此确认手机端保存提示及通过局域网IP的后端认证连接已通过用户实测；实际餐食照片分析、编辑确认和重启后照片/记录保留仍待验证。此反馈不代表新的模型生成或餐食估算质量验收。

真机升级证据：`/private/tmp/FuelForm-deepseek-install-20261013.json`、`/private/tmp/FuelForm-deepseek-launch-20261013.json`、`/private/tmp/FuelForm-deepseek-process-20261013.json`。没有卸载或重置手机数据，服务凭据由用户自行在手机保存。

用户要求推送本轮修改。推送前再次运行 `./scripts/verify.sh`：项目结构检查、49项后端测试及20项Foundation检查通过；核对最终24项原生XCTest和Debug真机/Release模拟器构建成功记录。确认真实 `.env`被忽略，待提交文件未包含本机配置的密钥或服务令牌。此次发布范围为DeepSeek接入、局域网IP连接修复、状态/凭据反馈、测试和文档，不包含云端部署。

## 2026-10-13 追加：统一修复输入后键盘无法收起

用户再次报告文字输入后键盘无法收回。检查发现训练计划、AI目标、实际训练、食物详情及搜索缺少统一的收起入口；餐次页旧按钮只清除食物项FocusState，未绑定该焦点的备注仍可能保持编辑。仅让按钮可见或清除局部焦点不足以覆盖所有输入。

- 新增共用 `fuelKeyboardDismissal()`，在输入页面顶部提供键盘向下按钮，同时保留键盘工具栏按钮、滚动收起和提交结束编辑。
- 通过当前页面附着的UIView定位所属UIWindow并调用系统 `endEditing(true)`，结束当前输入，不依赖某个字段的FocusState，也不遍历或操作其他窗口。
- 应用于个人资料/服务配置、当天目标、餐次与备注、食物详情/搜索、手动和AI训练计划、动作目标、实际训练组记录与备注。没有全局点击手势，不吞掉列表、按钮或食用比例滑块的点击。
- 26项原生XCTest、0失败；新增真实UIWindow内数字UITextField及多行UITextView回归，确认结束编辑且原值保留。项目结构/Swift语法检查、Debug真机签名构建、Release模拟器构建通过。
- 模拟器实际展开资料页数字软件键盘并观察顶部及键盘工具栏收起入口；Device Hub坐标操作仍报noWindowsAvailable，未将按钮可见称为点击通过。
- 用户连接并解锁后，同Bundle ID签名覆盖安装与启动均success。用户在iPhone复核资料数字输入和记餐备注，明确反馈“可以收起，内容保留”。训练及搜索等其余输入页面使用同一机制，尚未逐字段进行完整真机触摸验收。

证据：`/private/tmp/FuelForm-keyboard-tests-20261013.log`及同名xcresult、`/private/tmp/FuelForm-keyboard-device-20261013.log`、`/private/tmp/FuelForm-keyboard-release-20261013.log`、`/private/tmp/FuelForm-keyboard-install-20261013.json`、`/private/tmp/FuelForm-keyboard-launch-20261013.json`。本轮没有调用真实模型或更改手机记录。

收尾时尝试再次运行完整 `./scripts/verify.sh`，自动审批因额度限制未能完成，动作未执行；没有绕过审批。该限制不影响此前已成功执行的26项原生测试、结构检查、Debug/Release构建与手机复核。

用户随后要求推送键盘修复。推送范围为统一输入控件、各输入页面接入、两项键盘回归测试、Xcode测试文件引用及文档；推送前重新核对已有原生测试/构建成功记录与 `git diff --check`，获取远端后无分歧。本机 `.env`保持忽略，未纳入提交。

## 2026-10-19 追加：后端可靠性与运行诊断第一轮

用户要求开始优化后端。先核验当前代码和依赖，原有49项后端测试全部通过。当前实测Python3.13.15、FastAPI0.143.0、Starlette1.7.0、HTTPX0.28.1，未升级依赖。

本轮完成：

- BackendRuntime按照片/训练角色按需复用模型连接，在FastAPI lifespan退出时统一关闭；一次关闭失败仍尝试释放另一个连接。状态查询不初始化模型连接，没有缓存图片或分析结果。
- RequestGuard在读取上传前检查严格Bearer认证；AI请求单worker默认最多2个同时处理，20次/分钟，忙时503不排队，限流429返回Retry-After，不自动重试。健康/状态查询不占AI槽位。
- 对请求声明长度和实际字节计数，照片保留原MAX_IMAGE_BYTES加256KiB multipart边界，其他写入请求64KiB；上传总时限默认15秒。成功、错误、上传断开和ASGI任务取消释放槽位。
- 每次响应生成X-Request-ID、禁用缓存，只记录编号/固定路由/状态/耗时；不采信传入编号，不打印查询参数、令牌、照片、训练条件或上游异常正文。请求验证错误不回显输入，未预期错误返回安全500，配置校验异常文本隐藏输入。
- 新增check_backend.py，只GET健康与认证状态，不调用模型、不跟随重定向、不使用环境代理、不输出服务原始响应。smoke_backend.py增加可选URL与--no-write-fixtures，保留原默认行为；测试确认遇到真实供应商会在POST前停止。
- 新增可选并发和上传时限配置，未覆盖现有.env或切换供应商。运行说明记录单worker限制、错误码、重启生效和后续HTTPS部署要求。

验证：最终 `./scripts/verify.sh` 成功，79项后端pytest及20项Foundation检查通过，结构检查和 `git diff --check` 通过。新增测试覆盖早期认证、流式大小限制、上传超时、并发拒绝且健康可用、限流窗口边界、取消/异常释放、连接复用和关闭、隐私日志及诊断凭据不跟随重定向；这些不代表真实模型质量验证。

实际运行独立的127.0.0.1:18000 Mock服务，使用合成服务令牌完成新诊断脚本、合成JPEG multipart分析及两周计划HTTP联调；模式始终明确Mock，仓库契约样本未改写。日志只包含安全元数据。证据：`/private/tmp/FuelForm-backend-reliability-20261019.log`及本轮工具HTTP输出。最终测试服务由本任务关闭，没有替换或重启用户既有服务。

边界：本轮没有真实模型请求、手机数据变更、iOS代码修改或新的iOS/真机验收；没有云端部署，也未测得具体延迟下降。手机上传完成后断开网络是否立即取消上游仍待验证，不能保证取消免计费；没有请求幂等/结果缓存。现有限流属于单worker，不能用于多个实例的共享额度。代码重启后生效。

用户随后要求推送本轮修改。推送前重新执行 `./scripts/verify.sh`，79项后端测试和20项Foundation检查通过；fetch后main与origin/main无分歧。推送范围仅为后端实现、测试、诊断脚本与文档；本机.env保持忽略，检查确认改动中不含已配置的凭据。Git推送不代表服务已重启或完成部署。
