# FuelForm

个人 iPhone App，iOS 17+。原生 SwiftUI + SwiftData；后端 FastAPI 只做分析与计划草稿，不存个人历史。

## 结构与运行

- `ios/FuelForm/Core`：Foundation 业务模型、计算、API DTO；`Persistence`：SwiftData 版本化信封；`Services`：URLSession / Keychain / 照片；`Views`：中文界面。
- 工程：`python3 scripts/generate_xcode.py`，可用 `--bundle-id` / `--team-id`；会覆盖工程中的手工签名设置。
- 后端：`backend/.venv/bin/python -m uvicorn app.main:app --app-dir backend --host 127.0.0.1 --port 8000 --no-access-log`。
- `.env` 的生成：`python3 scripts/bootstrap_backend.py`，不输出凭据，不覆盖已有文件。
- 环境允许的验证：`./scripts/verify.sh`。`scripts/smoke_backend.py` 对运行中的 Mock 服务做实际 HTTP 验证。
- XCTest 的持久化测试需完整 Xcode / iOS 模拟器；见 `docs/acceptance.md`。缺少 SDK 时不能声称 App 编译或真机通过。当前已在Xcode27/iOS27完成Debug/Release构建和22项XCTest，已验收手动记餐/目标/训练及App重启；照片/AI、完整UI/真机仍待。
- 模拟器使用SDK条件化的私有Keychain entitlement；真机沿用真实Team，不禁用签名来跑Keychain验收。Keychain测试必须用隔离账号，不能覆盖用户token。

## 数据规则

- SwiftData 是唯一个人记录主存储，照片为 Application Support/Photos 下相对路径。使用 stable UUID；日期快照用 YYYY-MM-DD。
- 草稿不计入摄入。供餐重量 × 食用比例 = 实吃重量，只扣一次。未知重量为 nil，整餐总热量不按重量缩放。
- 数据库按每 100 g 计算；AI 无匹配时按整份估算且明确来源。编辑来源值要保留原分析，历史营养值不得随库更新重算。
- UTC ISO8601 时间戳，餐次归属按录入时当地公历日固定，补录不改为今天；按日历加减天，不用秒数推算日期。
- 每日目标/消耗是快照，改资料不能暗改历史。未记录不等于零，未记全不称全天缺口。
- 计划与实际日志分开；修改/删除计划不改写历史。休息日无未完成任务；计划训练不得推算为消耗。
- 确认餐次按同一 UUID upsert；训练按安排 ID + 日期去重。
- 删除照片前查所有餐次（含草稿）引用；成功保存后才删文件。迁移失败保留原存储，不做 reset。
- 模型 Key 仅后端；服务令牌仅 iOS Keychain。禁止日志记录完整图片、敏感请求及令牌。
- 演示餐次isDemo分区，不计个人摄入；演示计划禁止直接启用，需明确核对并转为个人草稿。
- Mock 始终显示演示；真实配置缺失/错误不得降级 Mock。没有凭据时继续测试 Mock 并记录限制。
- JSON 导出包含版本、完整领域记录和照片路径，不包含照片文件，也没有恢复功能。

不引入网页替代、云个人数据库、HealthKit、惩罚性训练或复杂 Agent 框架。常规实现自主推进，结果更新 `docs/progress.md`。
