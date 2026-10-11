#if SWIFT_PACKAGE
@main struct Runner {
    static func main() throws {
        let t = DomainTests()
        try t.testDraftConfirmationEditDeleteAndIdempotency()
        try t.testDemoRecordsStaySeparateFromPersonalIntakeAndPlan()
        try t.testServedActualWeightAndFractionAreAppliedOnce()
        try t.testRemainingAndDeficitAreDistinctAndMayBeNegative()
        try t.testMissingDayAndIncompleteDayAreNotFullDayResults()
        t.testExplicitCompleteZeroIntakeIsKnown()
        try t.testCurrentProfileDoesNotRewriteDailySnapshots()
        t.testMidnightBackdatingAndLeapDates()
        t.testDSTDayAdditionUsesCalendar()
        try t.testPlanEditingDoesNotChangeWorkoutSnapshotsOrDeficit()
        try t.testRestDaysAreNotWorkouts()
        try t.testCopyWeekMultiweekAndOverlapValidation()
        try t.testRawAnalysisAndNutritionHistorySurviveRoundTrip()
        t.testInvalidValuesFailBeforePersistence()
        try t.testReschedulingCreatesIndependentLogAndFutureCannotStart()
        try t.testSparseWeekCopyFillsUnscheduledDaysWithRest()
        let api = APIContractTests()
        try api.testBackendPhotoContractCalculatesActualIntake()
        try api.testBackendPlanContractProducesInactiveSnapshot()
        try api.testMalformedResponseAndDatesFailClientValidation()
        print("PASS: 19 FuelForm core business rule checks (Foundation, no iOS runtime)")
    }
}
#endif
