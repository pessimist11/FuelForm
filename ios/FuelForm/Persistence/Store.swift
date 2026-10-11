import Foundation
import SwiftData
import Observation

// Codable domain aggregates retain frozen nutrition and workout snapshots.
// This stable envelope allows migrations of payloads without resetting the database.
enum FuelSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredRecord.self] }
    @Model final class StoredRecord {
        @Attribute(.unique) var key: String
        var kind: String
        var payload: Data
        var payloadVersion: Int
        var modifiedAt: Date
        init(key: String, kind: String, payload: Data) {
            self.key = key; self.kind = kind; self.payload = payload; payloadVersion = 1; modifiedAt = Date()
        }
    }
}
typealias StoredRecord = FuelSchemaV1.StoredRecord
enum FuelMigrations: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FuelSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor @Observable final class AppStore {
    private(set) var state: LocalState
    private let context: ModelContext
    let foods: [FoodDefinition]
    let exercises: [ExerciseDefinition]
    init(container: ModelContainer, cleanPhotosOnLoad: Bool = true) throws {
        context = ModelContext(container); context.autosaveEnabled = false
        foods = try Self.resource("foods.v1", as: FoodCatalog.self).foods
        exercises = try Self.resource("exercises.v1", as: [ExerciseDefinition].self)
        var loaded = LocalState()
        for record in try context.fetch(FetchDescriptor<StoredRecord>()) {
            guard record.payloadVersion == 1 else { throw DomainError.invalid("数据版本较新，请使用匹配的 App；原数据未修改") }
            let decoder = JSONCoding.decoder()
            switch record.kind {
            case "profile": loaded.profile = try decoder.decode(Profile.self, from: record.payload)
            case "meal": loaded.meals.append(try decoder.decode(Meal.self, from: record.payload))
            case "day": loaded.days.append(try decoder.decode(DaySnapshot.self, from: record.payload))
            case "plan": loaded.plans.append(try decoder.decode(TrainingPlan.self, from: record.payload))
            case "workout": loaded.workouts.append(try decoder.decode(WorkoutLog.self, from: record.payload))
            case "weight": loaded.weights.append(try decoder.decode(WeightEntry.self, from: record.payload))
            default: throw DomainError.invalid("存在未知记录类型，停止加载以保留数据")
            }
        }
        state = loaded
        if cleanPhotosOnLoad { try? PhotoFiles.cleanOrphans(referenced: Set(loaded.meals.compactMap(\.photoPath))) }
    }
    private struct FoodCatalog: Decodable { var version: String; var foods: [FoodDefinition] }
    private static func resource<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { throw DomainError.invalid("缺少离线数据文件 \(name)") }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    func change(_ edit: (inout LocalState) throws -> Void) throws {
        var next = state; try edit(&next)
        let existing = try context.fetch(FetchDescriptor<StoredRecord>())
        var byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
        let encoder = JSONCoding.encoder()
        func put<T: Encodable>(_ value: T, kind: String, id: String) throws {
            let key = kind + ":" + id; let data = try encoder.encode(value)
            if let record = byKey.removeValue(forKey: key) {
                if record.payload != data { record.payload = data; record.modifiedAt = Date() }
            } else { context.insert(StoredRecord(key: key, kind: kind, payload: data)) }
        }
        do {
            try put(next.profile, kind: "profile", id: "personal")
            for v in next.meals { try put(v, kind: "meal", id: v.id.uuidString) }
            for v in next.days { try put(v, kind: "day", id: v.dayKey) }
            for v in next.plans { try put(v, kind: "plan", id: v.id.uuidString) }
            for v in next.workouts { try put(v, kind: "workout", id: v.id.uuidString) }
            for v in next.weights { try put(v, kind: "weight", id: v.id.uuidString) }
            for record in byKey.values { context.delete(record) }
            try context.save()
            let oldPaths = Set(state.meals.compactMap(\.photoPath)); state = next
            for path in oldPaths.subtracting(Set(next.meals.compactMap(\.photoPath))) { try? PhotoFiles.remove(path) }
        } catch { context.rollback(); throw error }
    }
    func saveMeal(_ meal: Meal) throws { try change { try $0.upsert(meal) } }
    func deleteMeal(_ id: UUID) throws { try change { $0.meals.removeAll { $0.id == id } } }
    func savePlan(_ plan: TrainingPlan) throws { try change { try $0.savePlan(plan) } }
    func saveWorkout(_ log: WorkoutLog) throws { try change { try $0.saveWorkout(log) } }
    func startWorkout(_ plan: TrainingPlan, _ day: PlanDay) throws -> WorkoutLog {
        var result: WorkoutLog?
        try change { result = try $0.startWorkout(plan: plan, day: day) }
        return result!
    }
    func saveProfile(_ profile: Profile, applyToday: Bool) throws {
        try profile.validate()
        try change {
            $0.profile = profile
            if applyToday {
                let key = DayKey.make(Date()); $0.ensureDay(key)
                if let i = $0.days.firstIndex(where: { $0.dayKey == key }) { $0.days[i].intakeTarget = profile.intakeTarget; $0.days[i].expenditure = profile.expenditure }
            }
        }
    }
    func export() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FuelFormExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep only the latest generated export within the app; user-chosen external copies are independent.
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: url) }
        let url = directory.appendingPathComponent("FuelForm-\(DayKey.make(Date())).json")
        try JSONCoding.encoder().encode(ExportArchive(state: state)).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
