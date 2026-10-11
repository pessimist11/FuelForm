import Foundation
#if !SWIFT_PACKAGE && canImport(XCTest)
import XCTest
#else
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { precondition(a == b, "Expected equality: \(a) vs \(b) at \(file):\(line)") }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double) { precondition(abs(a-b) <= accuracy) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a != b) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) { do { _ = try expression(); preconditionFailure("Expected thrown error") } catch {} }
#endif
#if canImport(FuelFormCore)
@testable import FuelFormCore
#else
@testable import FuelForm
#endif

final class DomainTests: XCTestCase {
    func meal(_ kcal: Double, confirmed: Bool = true, key: String = "2026-10-10") -> Meal {
        var m = Meal(); m.dayKey = key; m.confirmed = confirmed
        var f = FoodItem(); f.name = "测试食物"; f.nutrients.kcal = kcal; m.items = [f]; return m
    }
    func testDraftConfirmationEditDeleteAndIdempotency() throws {
        var state = LocalState(); state.profile.intakeTarget = 1800; state.profile.expenditure = 2200
        var m = meal(400, confirmed: false); try state.upsert(m)
        XCTAssertEqual(state.summary(m.dayKey).intake, 0); XCTAssertNil(state.summary(m.dayKey).deficit)
        m.confirmed = true; try state.upsert(m); try state.upsert(m)
        XCTAssertEqual(state.meals.count, 1); XCTAssertEqual(state.summary(m.dayKey).intake, 400)
        m.items[0].nutrients.kcal = 600; try state.upsert(m)
        XCTAssertEqual(state.summary(m.dayKey).intake, 600)
        state.meals.removeAll { $0.id == m.id }; XCTAssertEqual(state.summary(m.dayKey).intake, 0)
    }
    func testDemoRecordsStaySeparateFromPersonalIntakeAndPlan() throws {
        var state = LocalState(); state.profile.expenditure = 2200
        var m = meal(195); m.isDemo = true; try state.upsert(m)
        XCTAssertEqual(state.summary(m.dayKey).intake, 0); XCTAssertNil(state.summary(m.dayKey).deficit)
        m.isDemo = false; m.confirmed = false; try state.upsert(m)
        XCTAssertEqual(state.summary(m.dayKey).intake, 0)
        m.confirmed = true; try state.upsert(m); XCTAssertEqual(state.summary(m.dayKey).intake, 195)
        var p = plan(); p.demo = true; XCTAssertThrowsError(try state.savePlan(p))
        p.active = false; try state.savePlan(p); XCTAssertFalse(state.plans[0].active)
    }
    func testServedActualWeightAndFractionAreAppliedOnce() throws {
        var f = FoodItem(); f.name = "熟饭"; f.servedGrams = 200; f.eatenFraction = 0.75; f.basis = "per100"
        f.nutrients = Nutrients(kcal: 130, protein: 2.69, carbs: 28.17, fat: 0.28)
        try f.validate(); XCTAssertEqual(f.actualGrams, 150); XCTAssertEqual(f.consumed.kcal, 195)
        XCTAssertEqual(f.consumed.protein!, 4.035, accuracy: 0.000001)
        f.basis = "total"; f.nutrients.kcal = 260; XCTAssertEqual(f.consumed.kcal, 195)
    }
    func testRemainingAndDeficitAreDistinctAndMayBeNegative() throws {
        var state = LocalState(); state.profile.intakeTarget = 1800; state.profile.expenditure = 2200
        let m = meal(2400); try state.upsert(m)
        XCTAssertEqual(state.summary(m.dayKey).remaining, -600); XCTAssertEqual(state.summary(m.dayKey).deficit, -200)
    }
    func testMissingDayAndIncompleteDayAreNotFullDayResults() throws {
        var state = LocalState(); state.profile.expenditure = 2200; state.ensureDay("2026-10-10")
        XCTAssertNil(state.summary("2026-10-10").deficit); XCTAssertFalse(state.summary("2026-10-10").isFullDay)
        try state.upsert(meal(600)); XCTAssertFalse(state.summary("2026-10-10").isFullDay)
        state.days[0].complete = true
        let tomorrow = DayKey.date("2026-10-11")!
        XCTAssertTrue(state.summary("2026-10-10", now: tomorrow).isFullDay)
        XCTAssertFalse(state.summary("2026-10-10", now: DayKey.date("2026-10-10")!).isFullDay)
    }
    func testExplicitCompleteZeroIntakeIsKnown() {
        var state = LocalState(); state.profile.expenditure = 2000; state.ensureDay("2026-10-10"); state.days[0].complete = true
        XCTAssertEqual(state.summary("2026-10-10").deficit, 2000)
    }
    func testCurrentProfileDoesNotRewriteDailySnapshots() throws {
        var state = LocalState(); state.profile.intakeTarget = 1800; state.profile.expenditure = 2200
        try state.upsert(meal(600)); state.profile.intakeTarget = 1900; state.profile.expenditure = 2300
        try state.upsert(meal(100)); state.ensureDay("2026-10-11")
        XCTAssertEqual(state.days[0].intakeTarget, 1800); XCTAssertEqual(state.days[0].expenditure, 2200)
        XCTAssertEqual(state.days[1].intakeTarget, 1900)
    }
    func testMidnightBackdatingAndLeapDates() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let a = ISO8601DateFormatter().date(from: "2026-10-10T15:59:59Z")!
        let b = ISO8601DateFormatter().date(from: "2026-10-10T16:00:00Z")!
        XCTAssertEqual(DayKey.make(a, timeZone: zone), "2026-10-10")
        XCTAssertEqual(DayKey.make(b, timeZone: zone), "2026-10-11")
        XCTAssertEqual(DayKey.make(a, timeZone: TimeZone(secondsFromGMT: 0)!), "2026-10-10")
        XCTAssertFalse(DayKey.valid("2026-02-29")); XCTAssertTrue(DayKey.valid("2024-02-29"))
        XCTAssertEqual(DayKey.adding(1, to: "2024-02-28"), "2024-02-29")
        var m = meal(200); m.occurredAt = a; m.dayKey = DayKey.make(a, timeZone: zone)
        XCTAssertEqual(m.dayKey, "2026-10-10") // Backdate remains stable even when viewed in another timezone
    }
    func testDSTDayAdditionUsesCalendar() {
        let zone = TimeZone(identifier: "America/New_York")!
        let first = DayKey.date("2026-03-08", timeZone: zone)!
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        XCTAssertEqual(DayKey.make(c.date(byAdding: .day, value: 1, to: first)!, timeZone: zone), "2026-03-09")
    }
    func plan() -> TrainingPlan {
        var p = TrainingPlan(); p.active = true; var d = PlanDay(); d.dayKey = "2026-10-10"; d.exercises = [PlannedExercise()]; p.days = [d]; return p
    }
    func testPlanEditingDoesNotChangeWorkoutSnapshotsOrDeficit() throws {
        var state = LocalState(); state.profile.expenditure = 2200; try state.upsert(meal(600))
        var p = plan(); try state.savePlan(p); let day = p.days[0]
        let original = try state.startWorkout(plan: p, day: day)
        XCTAssertEqual(try state.startWorkout(plan: p, day: day).id, original.id); XCTAssertEqual(state.workouts.count, 1)
        p.days[0].exercises[0].name = "新动作"; p.days[0].exercises[0].sets = 5; try state.savePlan(p)
        XCTAssertEqual(state.workouts[0].exercises[0].planned.name, "徒手深蹲"); XCTAssertEqual(state.workouts[0].exercises[0].sets.count, 3)
        XCTAssertEqual(state.summary("2026-10-10").deficit, 1600)
    }
    func testRestDaysAreNotWorkouts() throws {
        var state = LocalState(); let p = plan(); var d = p.days[0]; d.rest = true; d.exercises = []
        try d.validate(); XCTAssertThrowsError(try state.startWorkout(plan: p, day: d))
    }
    func testCopyWeekMultiweekAndOverlapValidation() throws {
        var p = plan(); for n in 1..<7 { var d = PlanDay(); d.dayKey = DayKey.adding(n, to: "2026-10-10"); d.rest = true; p.days.append(d) }
        let copy = try p.copyWeek(start: "2026-11-01", weeks: 3)
        XCTAssertEqual(copy.days.count, 21); XCTAssertEqual(copy.days.last?.dayKey, "2026-11-21"); XCTAssertFalse(copy.active)
        XCTAssertNotEqual(copy.days[0].id, p.days[0].id)
        var state = LocalState(); try state.savePlan(p); var conflict = p; conflict.id = UUID()
        XCTAssertThrowsError(try state.savePlan(conflict))
    }
    func testReschedulingCreatesIndependentLogAndFutureCannotStart() throws {
        var state = LocalState(); var p = plan()
        let now = DayKey.date("2026-10-13")!
        let old = try state.startWorkout(plan: p, day: p.days[0], now: now)
        p.days[0].dayKey = "2026-10-12"
        let new = try state.startWorkout(plan: p, day: p.days[0], now: now)
        XCTAssertNotEqual(old.id, new.id); XCTAssertEqual(state.workouts[0].dayKey, "2026-10-10")
        p.days[0].dayKey = "2026-10-14"
        XCTAssertThrowsError(try state.startWorkout(plan: p, day: p.days[0], now: now))
    }
    func testSparseWeekCopyFillsUnscheduledDaysWithRest() throws {
        let p = plan(); let copy = try p.copyWeek(start: "2026-11-01", weeks: 2)
        XCTAssertEqual(copy.days.count, 14); XCTAssertEqual(copy.days.filter(\.rest).count, 12)
        XCTAssertEqual(copy.days.filter { !$0.rest }.count, 2)
    }
    func testRawAnalysisAndNutritionHistorySurviveRoundTrip() throws {
        var state = LocalState(); var m = meal(300); m.rawAnalyses = ["original AI JSON"]
        m.items[0].source = FoodSource(kind: "ai", label: "AI 估算"); try state.upsert(m)
        m.items[0].nutrients.kcal = 400; try state.upsert(m)
        let data = try JSONCoding.encoder().encode(ExportArchive(state: state))
        let result = try JSONCoding.decoder().decode(ExportArchive.self, from: data)
        XCTAssertEqual(result.formatVersion, 1); XCTAssertFalse(result.photosIncluded)
        XCTAssertEqual(result.state.meals[0].rawAnalyses, ["original AI JSON"]); XCTAssertEqual(result.state.meals[0].kcal, 400)
    }
    func testInvalidValuesFailBeforePersistence() {
        var m = meal(400); m.items[0].eatenFraction = 1.2; XCTAssertThrowsError(try m.validate())
        m.items[0].eatenFraction = 1; m.items[0].nutrients.kcal = .nan; XCTAssertThrowsError(try m.validate())
        var p = plan(); p.days[0].exercises[0].maxReps = 2; XCTAssertThrowsError(try p.validate())
        var profile = Profile(); profile.age = 0; XCTAssertThrowsError(try profile.validate())
    }
}
