import Foundation

public struct SuggestedFood: Codable, Sendable {
    public var name: String
    public var servedGrams: Double
    public var preparation: String
    public var basis: String
    public var nutrients: Nutrients
    public var source: FoodSource
    public var assumptions: [String]
    public var questions: [String]
    public func item() throws -> FoodItem {
        var f = FoodItem(); f.name = name; f.servedGrams = servedGrams; f.preparation = preparation; f.basis = basis
        f.nutrients = nutrients; f.source = source; f.assumptions = assumptions; f.questions = questions
        try f.validate(); return f
    }
}
public struct OriginalRecognition: Codable, Sendable {
    public var isFood: Bool
    public var items: [Candidate]
    public var message: String
    public struct Candidate: Codable, Sendable {
        public var name: String
        public var foodId: String?
        public var servedGrams: Double
        public var preparation: String
        public var estimatedNutrients: Nutrients
        public var assumptions: [String]
        public var questions: [String]
    }
}
public struct AnalysisResponse: Codable, Sendable {
    public var originalDraft: OriginalRecognition? = nil
    public var mode: String
    public var isFood: Bool
    public var items: [SuggestedFood]
    public var message: String
    public var warnings: [String]
    public var catalogVersion: String
    public func validatedItems() throws -> [FoodItem] {
        guard ["mock", "openai", "deepseek"].contains(mode), isFood == !items.isEmpty, items.count <= 30 else { throw DomainError.invalid("分析响应不合理") }
        return try items.map { try $0.item() }
    }
}
public struct AIPlanRequest: Codable, Sendable {
    public var startDate: String
    public var weeks: Int
    public var trainingDays: Int
    public var durationMinutes: Int
    public var equipment: [String]
    public var experience: String
    public var goal: String
    public var avoidExerciseIds: [String]
    public init(startDate: String, weeks: Int, trainingDays: Int, durationMinutes: Int, equipment: [String], experience: String, goal: String, avoidExerciseIds: [String]) {
        self.startDate = startDate; self.weeks = weeks; self.trainingDays = trainingDays; self.durationMinutes = durationMinutes; self.equipment = equipment; self.experience = experience; self.goal = goal; self.avoidExerciseIds = avoidExerciseIds
    }
}
public struct AIPlanResponse: Codable, Sendable {
    public var mode: String
    public var draft: Draft
    public var warnings: [String]
    public struct Draft: Codable, Sendable {
        public var name: String; public var days: [Day]; public var notes: String
    }
    public struct Day: Codable, Sendable {
        public var dayKey: String; public var rest: Bool; public var exercises: [Exercise]
    }
    public struct Exercise: Codable, Sendable {
        public var exerciseId: String; public var name: String; public var sets: Int; public var minReps: Int
        public var maxReps: Int; public var targetKg: Double?; public var restSeconds: Int
    }
    public func plan(exercises: [ExerciseDefinition], request: AIPlanRequest) throws -> TrainingPlan {
        guard ["mock", "openai", "deepseek"].contains(mode), draft.days.count == request.weeks * 7 else { throw DomainError.invalid("AI 计划长度无效") }
        var p = TrainingPlan(); p.name = draft.name; p.demo = mode == "mock"; p.notes = draft.notes + "\n" + warnings.joined(separator: "\n")
        p.days = try draft.days.enumerated().map { offset, input in
            guard input.dayKey == DayKey.adding(offset, to: request.startDate) else { throw DomainError.invalid("AI 计划日期无效") }
            var d = PlanDay(); d.dayKey = input.dayKey; d.rest = input.rest
            d.exercises = try input.exercises.map { item in
                guard let known = exercises.first(where: { $0.id == item.exerciseId }), request.equipment.contains(known.equipment), !request.avoidExerciseIds.contains(item.exerciseId) else { throw DomainError.invalid("AI 使用未知或需要避开的动作") }
                var e = PlannedExercise(); e.exerciseID = item.exerciseId; e.name = known.name; e.sets = item.sets
                e.minReps = item.minReps; e.maxReps = item.maxReps; e.targetKG = item.targetKg; e.restSeconds = item.restSeconds
                try e.validate(); return e
            }; return d
        }
        for week in 0..<request.weeks {
            guard p.days[(week * 7)..<(week * 7 + 7)].filter({ !$0.rest }).count == request.trainingDays else { throw DomainError.invalid("AI 每周训练天数不符合请求") }
        }
        try p.validate(); return p
    }
}
