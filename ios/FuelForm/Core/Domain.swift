import Foundation

public enum DomainError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
public struct Nutrients: Codable, Equatable, Sendable {
    public var kcal: Double
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public init(kcal: Double = 0, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat
    }
    public func scaled(_ factor: Double) -> Self {
        Self(kcal: kcal * factor, protein: protein.map { $0 * factor }, carbs: carbs.map { $0 * factor }, fat: fat.map { $0 * factor })
    }
    public func validate() throws {
        guard [kcal, protein, carbs, fat].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw DomainError.invalid("营养值必须是非负有限数值") }
    }
}
public struct FoodSource: Codable, Equatable, Sendable {
    public var kind: String // database, ai, manual, demo
    public var label: String
    public var version: String
    public var reference: String?
    public init(kind: String = "manual", label: String = "手动录入", version: String = "1", reference: String? = nil) {
        self.kind = kind; self.label = label; self.version = version; self.reference = reference
    }
}
public struct FoodItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var servedGrams: Double? = nil
    public var eatenFraction: Double = 1
    public var basis: String = "total" // per100 or total supplied serving
    public var nutrients: Nutrients = Nutrients()
    public var preparation: String = "未知"
    public var source: FoodSource = FoodSource()
    public var assumptions: [String] = []
    public var questions: [String] = []
    public var actualGrams: Double? { servedGrams.map { $0 * eatenFraction } }
    public var consumed: Nutrients { nutrients.scaled(basis == "per100" ? (actualGrams ?? 0) / 100 : eatenFraction) }
    public init() {}
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
              servedGrams.map({ $0.isFinite && $0 > 0 && $0 <= 10000 }) ?? (basis == "total"),
              eatenFraction.isFinite, (0...1).contains(eatenFraction), ["per100", "total"].contains(basis),
              ["database", "ai", "manual", "demo"].contains(source.kind) else { throw DomainError.invalid("请检查食物名称、供餐重量和食用比例") }
        try nutrients.validate()
    }
}
public struct FoodDefinition: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var preparation: String
    public var aliases: [String]
    public var nutrients: Nutrients
    public var source: FoodSource
    public func item() -> FoodItem {
        var item = FoodItem(); item.name = name; item.preparation = preparation; item.nutrients = nutrients
        item.source = source; item.servedGrams = 100; item.basis = "per100"; return item
    }
}
public enum MealKind: String, CaseIterable, Codable, Sendable { case breakfast = "早餐", lunch = "午餐", dinner = "晚餐", snack = "加餐" }
public struct Meal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var occurredAt: Date = Date() // Codable ISO8601 UTC; dayKey fixed to local day at entry
    public var dayKey: String = DayKey.make(Date())
    public var timeZoneID: String = TimeZone.current.identifier
    public var kind: MealKind = .lunch
    public var confirmed: Bool = false
    public var isDemo: Bool = false
    public var items: [FoodItem] = []
    public var photoPath: String?
    public var rawAnalyses: [String] = [] // Append only: initial provider response retained separately from edits
    public var notes: String = ""
    public var kcal: Double { items.reduce(0) { $0 + $1.consumed.kcal } }
    public init() {}
    public func validate() throws {
        guard (confirmed ? !items.isEmpty : (!items.isEmpty || photoPath != nil)), items.count <= 50, DayKey.valid(dayKey), occurredAt.timeIntervalSince1970.isFinite else { throw DomainError.invalid("餐次至少包含一项食物，日期必须有效") }
        for item in items { try item.validate() }
    }
}
public enum DayKey {
    public static func make(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func date(_ key: String, timeZone: TimeZone = .current) -> Date? {
        guard key.count == 10, key.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }; guard parts.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        guard let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)), make(date, timeZone: timeZone) == key else { return nil }; return date
    }
    public static func valid(_ key: String) -> Bool { date(key) != nil }
    public static func adding(_ days: Int, to key: String) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        guard let date = date(key), let result = cal.date(byAdding: .day, value: days, to: date) else { return key }
        return make(result)
    }
}
public struct Profile: Codable, Equatable, Sendable {
    public var heightCM: Double?
    public var weightKG: Double?
    public var age: Int?
    public var sex: String = "未填写"
    public var activity: String = "未填写"
    public var intakeTarget: Double?
    public var expenditure: Double? // Manual estimate only, no invented body defaults
    public init() {}
    public func validate() throws {
        for (value, maximum) in [(heightCM, 300.0), (weightKG, 500.0), (intakeTarget, 10000.0), (expenditure, 15000.0)] {
            if let value { guard value.isFinite && value > 0 && value <= maximum else { throw DomainError.invalid("资料和目标必须填写有效正数，或留空") } }
        }
        if let age, !(1...120).contains(age) { throw DomainError.invalid("年龄应为 1–120") }
    }
}
public struct WeightEntry: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var date: Date
    public var kg: Double
    public init(date: Date = Date(), kg: Double) { self.date = date; self.kg = kg }
}
public struct DaySnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var intakeTarget: Double?
    public var expenditure: Double?
    public var estimateMethod: String = "手动设置的估算总消耗；不包含计划训练推算"
    public var createdAt: Date = Date()
    public var complete: Bool = false
    public init(dayKey: String, profile: Profile) { self.dayKey = dayKey; intakeTarget = profile.intakeTarget; expenditure = profile.expenditure }
}
public struct DaySummary: Equatable, Sendable {
    public var intake: Double
    public var remaining: Double?
    public var deficit: Double?
    public var hasRecords: Bool
    public var isFullDay: Bool
    public var status: String { isFullDay ? "已确认记全 · 仍为估算" : (hasRecords ? "截至目前已记录 · 非全天结果" : "尚无已确认记录 · 实际摄入未知") }
    public static func calculate(dayKey: String, meals: [Meal], snapshot: DaySnapshot?, now: Date = Date()) -> Self {
        let confirmed = meals.filter { $0.confirmed && !$0.isDemo && $0.dayKey == dayKey }
        let intake = confirmed.reduce(0) { $0 + $1.kcal }
        let known = !confirmed.isEmpty || snapshot?.complete == true
        return Self(intake: intake, remaining: known ? snapshot?.intakeTarget.map { $0 - intake } : nil,
                    deficit: known ? snapshot?.expenditure.map { $0 - intake } : nil, hasRecords: !confirmed.isEmpty,
                    isFullDay: snapshot?.complete == true && dayKey < DayKey.make(now))
    }
}
public struct ExerciseDefinition: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var equipment: String
    public var cue: String
}
public struct PlannedExercise: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var exerciseID: String = "squat"
    public var name: String = "徒手深蹲"
    public var sets: Int = 3
    public var minReps: Int = 8
    public var maxReps: Int = 12
    public var targetKG: Double?
    public var restSeconds: Int = 90
    public init() {}
    public func validate() throws {
        guard !name.isEmpty, (1...10).contains(sets), (1...100).contains(minReps), (minReps...100).contains(maxReps), (15...600).contains(restSeconds), targetKG.map({ $0.isFinite && $0 >= 0 && $0 <= 500 }) ?? true else { throw DomainError.invalid("动作组数、次数、重量或休息时间不合理") }
    }
}
public struct PlanDay: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var dayKey: String = DayKey.make(Date())
    public var rest: Bool = false
    public var exercises: [PlannedExercise] = []
    public init() {}
    public func validate() throws {
        guard DayKey.valid(dayKey), exercises.count <= 12, rest ? exercises.isEmpty : !exercises.isEmpty else { throw DomainError.invalid("休息日应为空，训练日至少有一个动作") }
        for exercise in exercises { try exercise.validate() }
    }
}
public struct TrainingPlan: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String = "我的训练计划"
    public var active: Bool = false
    public var demo: Bool = false
    public var days: [PlanDay] = []
    public var rawAI: String?
    public var notes: String = ""
    public init() {}
    public func validate() throws {
        guard !name.isEmpty, !days.isEmpty, days.count <= 84, Set(days.map(\.dayKey)).count == days.count else { throw DomainError.invalid("计划名称、日期数量或重复日期有误") }
        for day in days { try day.validate() }
    }
    public func copyWeek(start: String, weeks: Int) throws -> Self {
        guard (1...12).contains(weeks), DayKey.valid(start) else { throw DomainError.invalid("周数应为 1–12") }
        var copy = self; copy.id = UUID(); copy.active = false; copy.name += " · 复制"; copy.rawAI = nil; copy.days = []
        guard let base = days.map(\.dayKey).min() else { throw DomainError.invalid("没有可复制的周计划") }
        for week in 0..<weeks {
            for offset in 0..<7 {
                let sourceKey = DayKey.adding(offset, to: base)
                var day = days.first(where: { $0.dayKey == sourceKey }) ?? PlanDay()
                if !days.contains(where: { $0.dayKey == sourceKey }) { day.rest = true }
                day.id = UUID(); day.dayKey = DayKey.adding(week * 7 + offset, to: start)
                day.exercises = day.exercises.map { var e = $0; e.id = UUID(); return e }
                copy.days.append(day)
            }
        }
        try copy.validate(); return copy
    }
}
public struct SetLog: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var reps: Int = 0
    public var kg: Double = 0
    public var completed: Bool = false
    public init() {}
}
public struct ExerciseLog: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var planned: PlannedExercise
    public var actualName: String
    public var actualExerciseID: String?
    public var status: String = "pending" // pending, completed, skipped
    public var sets: [SetLog]
    public init(planned: PlannedExercise) { self.planned = planned; actualName = planned.name; actualExerciseID = planned.exerciseID; sets = (0..<planned.sets).map { _ in SetLog() } }
}
public struct WorkoutLog: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var planID: UUID
    public var planDayID: UUID
    public var dayKey: String
    public var startedAt: Date = Date()
    public var finishedAt: Date?
    public var exercises: [ExerciseLog]
    public var notes: String = ""
    public init(plan: TrainingPlan, day: PlanDay) { planID = plan.id; planDayID = day.id; dayKey = day.dayKey; exercises = day.exercises.map { ExerciseLog(planned: $0) } }
    public func validate() throws {
        guard DayKey.valid(dayKey), !exercises.isEmpty else { throw DomainError.invalid("训练日志无动作或日期错误") }
        for e in exercises {
            guard !e.actualName.isEmpty, ["pending", "completed", "skipped"].contains(e.status), e.sets.count <= 20 else { throw DomainError.invalid("训练状态无效") }
            for s in e.sets { guard (0...1000).contains(s.reps), s.kg.isFinite, (0...500).contains(s.kg) else { throw DomainError.invalid("实际次数或重量无效") } }
        }
    }
}
public struct LocalState: Codable, Sendable {
    public var profile: Profile = Profile()
    public var meals: [Meal] = []
    public var days: [DaySnapshot] = []
    public var plans: [TrainingPlan] = []
    public var workouts: [WorkoutLog] = []
    public var weights: [WeightEntry] = []
    public init() {}
    public mutating func ensureDay(_ key: String) {
        if !days.contains(where: { $0.dayKey == key }) { days.append(DaySnapshot(dayKey: key, profile: profile)) }
    }
    public mutating func upsert(_ meal: Meal) throws {
        try meal.validate(); if !meal.isDemo { ensureDay(meal.dayKey) }
        if let i = meals.firstIndex(where: { $0.id == meal.id }) { meals[i] = meal } else { meals.append(meal) }
    }
    public func summary(_ key: String, now: Date = Date()) -> DaySummary {
        DaySummary.calculate(dayKey: key, meals: meals, snapshot: days.first { $0.dayKey == key }, now: now)
    }
    public mutating func savePlan(_ plan: TrainingPlan) throws {
        try plan.validate()
        guard !plan.demo || !plan.active else { throw DomainError.invalid("演示计划需明确转为个人草稿并核对后才能启用") }
        if plan.active {
            let incoming = Set(plan.days.map(\.dayKey))
            guard !plans.contains(where: { $0.active && $0.id != plan.id && !incoming.isDisjoint(with: Set($0.days.map(\.dayKey))) }) else { throw DomainError.invalid("已有启用计划占用这些日期，请先停用或调整日期") }
        }
        if let i = plans.firstIndex(where: { $0.id == plan.id }) { plans[i] = plan } else { plans.append(plan) }
    }
    public mutating func startWorkout(plan: TrainingPlan, day: PlanDay, now: Date = Date()) throws -> WorkoutLog {
        guard day.dayKey <= DayKey.make(now), plan.days.contains(where: { $0.id == day.id }), plan.active, !plan.demo, !day.rest else { throw DomainError.invalid("休息日或未启用计划无需打卡") }
        if let existing = workouts.first(where: { $0.planDayID == day.id && $0.dayKey == day.dayKey }) { return existing }
        let log = WorkoutLog(plan: plan, day: day); workouts.append(log); return log
    }
    public mutating func saveWorkout(_ log: WorkoutLog) throws {
        try log.validate()
        if let i = workouts.firstIndex(where: { $0.id == log.id }) { workouts[i] = log } else { workouts.append(log) }
    }
}
public enum JSONCoding {
    public static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
    public static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
public struct ExportArchive: Codable, Sendable {
    public var formatVersion: Int = 1
    public var schemaVersion: Int = 1
    public var exportedAt: Date = Date()
    public var timeZoneID: String = TimeZone.current.identifier
    public var photosIncluded: Bool = false
    public var photoNotice: String = "仅包含照片相对路径，不含照片文件；此 JSON 不是完整备份，暂不支持恢复"
    public var state: LocalState
    public init(state: LocalState) { self.state = state }
}
