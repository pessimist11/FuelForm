import XCTest
import SwiftData
@testable import FuelForm

@MainActor final class PersistenceTests: XCTestCase {
    func testDiskRelaunchOfflineRecordsAndDeletion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FuelForm-\(UUID().uuidString).store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema = Schema(versionedSchema: FuelSchemaV1.self)
        func container() throws -> ModelContainer {
            try ModelContainer(for: schema, migrationPlan: FuelMigrations.self, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        let id: UUID
        do {
            let store = try AppStore(container: container(), cleanPhotosOnLoad: false)
            var m = Meal(); var f = FoodItem(); f.name = "离线手动餐"; f.nutrients.kcal = 450; m.confirmed = true; m.items = [f]
            id = m.id; try store.saveMeal(m); try store.saveMeal(m)
            XCTAssertEqual(store.state.meals.count, 1)
            var plan = TrainingPlan(); plan.active = true; var d = PlanDay(); d.exercises = [PlannedExercise()]; plan.days = [d]
            try store.savePlan(plan); var log = try store.startWorkout(plan, d); log.exercises[0].sets[0].reps = 10; log.exercises[0].sets[0].completed = true; try store.saveWorkout(log)
        }
        let reopened = try AppStore(container: container(), cleanPhotosOnLoad: false)
        XCTAssertEqual(reopened.state.meals.first?.id, id)
        XCTAssertEqual(reopened.state.summary(DayKey.make(Date())).intake, 450)
        XCTAssertEqual(reopened.state.workouts.first?.exercises[0].sets[0].reps, 10)
        try reopened.deleteMeal(id)
        XCTAssertEqual(reopened.state.summary(DayKey.make(Date())).intake, 0)
    }
    func testPhotoReferenceDeletionKeepsSharedFiles() throws {
        let schema = Schema(versionedSchema: FuelSchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let store = try AppStore(container: container, cleanPhotosOnLoad: false)
        let path = "Photos/\(UUID().uuidString).jpg"; let url = try PhotoFiles.url(path); try Data([1,2,3]).write(to: url)
        var first = Meal(); first.photoPath = path; var second = first; second.id = UUID()
        try store.saveMeal(first); try store.saveMeal(second); try store.deleteMeal(first.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try store.deleteMeal(second.id); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
