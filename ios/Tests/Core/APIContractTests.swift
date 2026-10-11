import Foundation
#if !SWIFT_PACKAGE && canImport(XCTest)
import XCTest
#endif
#if canImport(FuelFormCore)
@testable import FuelFormCore
#else
@testable import FuelForm
#endif

final class APIContractTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        #else
        // Synthetic fixtures are included in the XCTest bundle, never personal data.
        guard let dir = Bundle(for: Self.self).resourceURL else { throw DomainError.invalid("Missing test resources") }
        #endif
        return try Data(contentsOf: dir.appendingPathComponent(name + ".json"))
    }
    func testBackendPhotoContractCalculatesActualIntake() throws {
        let response = try JSONDecoder().decode(AnalysisResponse.self, from: fixture("analysis"))
        let items = try response.validatedItems(); XCTAssertEqual(response.mode, "mock"); XCTAssertEqual(items.count, 1)
        XCTAssertEqual(response.originalDraft?.items[0].estimatedNutrients.kcal, 195); XCTAssertEqual(items[0].source.kind, "database"); XCTAssertEqual(items[0].consumed.kcal, 195)
        var item = items[0]; item.eatenFraction = 0.5; XCTAssertEqual(item.consumed.kcal, 97.5)
    }
    func testBackendPlanContractProducesInactiveSnapshot() throws {
        let request = try JSONDecoder().decode(AIPlanRequest.self, from: fixture("plan-request"))
        let response = try JSONDecoder().decode(AIPlanResponse.self, from: fixture("plan"))
        let definitions = [ExerciseDefinition(id: "squat", name: "徒手深蹲", equipment: "bodyweight", cue: ""), ExerciseDefinition(id: "bridge", name: "臀桥", equipment: "bodyweight", cue: ""), ExerciseDefinition(id: "deadbug", name: "死虫式", equipment: "bodyweight", cue: "")]
        let p = try response.plan(exercises: definitions, request: request)
        XCTAssertEqual(p.days.count, 14); XCTAssertFalse(p.active); XCTAssertTrue(p.demo)
        XCTAssertEqual(p.days.filter { !$0.rest }.count, 6)
        XCTAssertFalse(p.days.flatMap(\.exercises).contains { $0.exerciseID == "pushup" })
    }
    func testMalformedResponseAndDatesFailClientValidation() throws {
        var response = try JSONDecoder().decode(AnalysisResponse.self, from: fixture("analysis"))
        response.items[0].nutrients.kcal = -1; XCTAssertThrowsError(try response.validatedItems())
        var plan = try JSONDecoder().decode(AIPlanResponse.self, from: fixture("plan"))
        let request = try JSONDecoder().decode(AIPlanRequest.self, from: fixture("plan-request"))
        plan.draft.days[0].dayKey = "2026-10-13"
        XCTAssertThrowsError(try plan.plan(exercises: [], request: request))
    }
}
