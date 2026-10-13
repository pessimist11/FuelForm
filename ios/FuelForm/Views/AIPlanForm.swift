import SwiftUI

@MainActor struct AIPlanForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serviceURL") private var serviceURL = "http://localhost:8000"
    @State private var start = Date()
    @State private var weeks = 1
    @State private var trainingDays = 3
    @State private var minutes = 40
    @State private var equipment: Set<String> = ["bodyweight"]
    @State private var experience = "beginner"
    @State private var goal = "建立规律训练习惯"
    @State private var avoid: Set<String> = []
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var generated: TrainingPlan?
    @State private var status: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("训练条件") {
                    DatePicker("开始日期", selection: $start, displayedComponents: .date)
                    Stepper("\(weeks) 周", value: $weeks, in: 1...12)
                    Stepper("每周训练 \(trainingDays) 天", value: $trainingDays, in: 1...6)
                    Stepper("每次 \(minutes) 分钟", value: $minutes, in: 15...120, step: 5)
                    Picker("经验", selection: $experience) { Text("新手").tag("beginner"); Text("有基础").tag("intermediate"); Text("熟练").tag("advanced") }
                    TextField("训练目标", text: $goal, axis: .vertical)
                }
                Section("可用器械") {
                    ForEach(["bodyweight", "dumbbell", "barbell", "machine"], id: \.self) { key in Toggle(["bodyweight":"自重", "dumbbell":"哑铃", "barbell":"杠铃", "machine":"固定器械"][key]!, isOn: selection(key, in: $equipment)) }
                }
                Section("需要避开的动作") { ForEach(store.exercises) { e in Toggle(e.name, isOn: selection(e.id, in: $avoid)) } }
                Section {
                    Notice(text: "通过已配置的后端生成。后端为 Mock 时明确标为演示草稿；真实模式失败不会切换到演示。仅发送这些训练条件，不发送个人历史。")
                    if busy { HStack { ProgressView(); Text("正在生成…"); Button("取消") { task?.cancel() } } }
                    Button("生成并保存计划草稿") { generate() }.disabled(busy || equipment.isEmpty || goal.isEmpty)
                    if let status { Notice(text: status) }
                }
            }.navigationTitle("AI 计划草稿")
                .fuelKeyboardDismissal()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .sheet(item: $generated) { PlanEditor(initial: $0) }
                .fuelError($error)
        }.onDisappear { task?.cancel() }
    }
    private func selection(_ key: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(key) }, set: { if $0 { set.wrappedValue.insert(key) } else { set.wrappedValue.remove(key) } })
    }
    private func generate() {
        guard !busy else { return }; busy = true
        let request = AIPlanRequest(startDate: DayKey.make(start), weeks: weeks, trainingDays: trainingDays, durationMinutes: minutes, equipment: equipment.sorted(), experience: experience, goal: goal, avoidExerciseIds: avoid.sorted())
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let client = try APIClient(address: serviceURL, token: ServiceKeychain.read())
                let response = try await client.plan(request)
                try Task.checkCancellation()
                var p = try response.plan(exercises: store.exercises, request: request)
                p.rawAI = String(decoding: try JSONCoding.encoder().encode(response), as: UTF8.self)
                try store.savePlan(p); generated = p; status = p.demo ? "演示计划草稿已保存，尚未启用" : "AI 计划草稿已保存，尚未启用"
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
