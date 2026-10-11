# 数据模型、关联与升级

## SwiftData 主存储

`FuelSchemaV1.StoredRecord`：unique key、kind、payload(Data)、payloadVersion、modifiedAt。schema 1.0.0，payload 1，配置明确禁用 CloudKit。每个领域聚合一条记录，独立保存的 UUID/key 控制幂等。

| kind / key | 内容 | 关联与删除 |
| --- | --- | --- |
| profile:personal | 身高cm、体重kg、年龄、生理性别、活动水平、当前摄入目标与手动消耗 | 不存在时全空资料，不创建身体数据 |
| weight:UUID | UTC日期、kg | 独立记录；删除不改资料和其他记录 |
| day:YYYY-MM-DD | 当日目标、估算总消耗、估算方法、创建UTC时间、complete | 餐次删掉后快照仍在；当前设置不重写历史 |
| meal:UUID | UTC时间、固定dayKey、时区、餐次、confirmed、isDemo、食物值数组、照片路径、原始分析数组、备注 | 食物随餐次聚合删除；照片只在所有草稿/记录都无引用后删 |
| plan:UUID | 名称、active、demo、日期安排、动作目标、原始AI、备注 | 计划删除不级联实际日志 |
| workout:UUID | planID、planDayID、dayKey、记录开始UTC、结束UTC、独立动作/组副本 | 按安排ID+日期查已有日志；日期调整后可新建，旧日志保留 |

FoodItem：稳定 UUID；名称、servedGrams（未知可为nil）、eatenFraction、basis、kcal/P/C/F、烹饪状态、source、assumptions/questions。数据库和原始分析是历史值快照（含originalDraft模型候选与后端营养匹配响应），后来营养库更新不重算。手动修改营养、名称或烹饪状态会标记手动修订并保留原来源说明。重量/比例改变仅重新计算该编辑记录。

PlannedExercise：UUID、动作库ID、名称、sets、min/maxReps、可选targetKG、restSeconds。
ExerciseLog：实际 UUID、完整 planned 副本、实际动作名称/ID、状态；每组日志 UUID、reps、kg、completed。历史允许纠正真实日志，但编辑计划不自动改日志。`startedAt` 是进入实际记录流程的时间，补录的日归属由 dayKey 表达。

## 写入与文件安全

先在值副本中校验，再更新 SwiftData 记录并 `context.save()`，成功后才发布新 state；失败 rollback 并显示错误。autosave关闭，所有主记录保存入口经过AppStore。动作编辑自动保存实际日志。未完成的餐次/计划编辑只有点击保存后才持久化。

照片路径限定 `Photos/<file>`，拒绝 `..` 和多级路径。JPEG持久文件使用文件保护。餐次保存成功后清理失去引用的照片；清理失败不回滚已存记录。App成功加载时扫描并移除无引用的jpg，处理崩溃/放弃编辑留下的文件。加载失败不进行清理；持久化测试关闭此扫描，避免影响其他本机照片。删除单条餐次不删除仍被其他草稿使用的同一照片。

## 计算与日期

- 实吃g=供餐g×食用比例。
- per100：kcal=实吃g/100×每100g热量；total：kcal=整份供餐热量×食用比例，未知重量不虚构为100g。
- 摄入=已确认餐次之和；剩余额度=目标−摄入；估算缺口=估算总消耗−摄入。负值显示超过目标或估算盈余。
- 没有确认记录且未标记记全时，余额/缺口未知，不能解释为实际0摄入。过去日期只有用户标记记全才称全天结果，仍是估算。
- 时间统一ISO8601 UTC；归属按录入当地公历日保存。跨午夜刷新今日。日期加减采用Calendar，支持闰日/夏令时，不做24小时秒数推算。

## 迁移与导出

已有 `VersionedSchema` / `SchemaMigrationPlan`，V1无迁移步骤，**没有验证过一次真实版本升级**。下一版必须保留V1，新增V2和实际迁移步骤，或显式升级payloadVersion。迁移前备份并验证旧餐次营养、原始分析与训练日志未改变。未知payload版本/类型或解码失败停止加载，不清空数据库。

JSON：formatVersion=1、schemaVersion=1、exportedAt、timeZoneID、photosIncluded=false、photoNotice、完整 LocalState。包含所有领域记录、草稿、原始分析和照片相对路径；不含Keychain凭据、服务配置、模型Key或照片文件。不实现导入恢复。外部分享的文件由用户保存，App仅保留最近生成的临时导出。
