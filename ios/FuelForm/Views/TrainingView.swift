import SwiftUI

@MainActor struct TrainingView: View {
    @Environment(AppStore.self) private var store
    @State private var date = Date()
    @State private var editor: TrainingPlan?
    @State private var aiSheet = false
    @State private var error: String?
    var key: String { DayKey.make(date) }
    var body: some View {
        List {
            Section("选择日期") {
                DatePicker("训练日期", selection: $date, displayedComponents: .date)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(-3...3, id: \.self) { offset in
                            let d = DayKey.adding(offset, to: key)
                            Button { if let new = DayKey.date(d) { date = new } } label: {
                                VStack { Text(String(d.suffix(5))); Image(systemName: hasTraining(d) ? "dumbbell.fill" : "circle") }.font(.caption).padding(8).background(offset == 0 ? Color.teal.opacity(0.15) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.accessibilityLabel("\(d)\(hasTraining(d) ? "有训练" : "无训练或休息")")
                        }
                    }
                }
            }
            Section("当日安排") {
                let schedules = store.state.plans.filter(\.active).flatMap { p in p.days.filter { $0.dayKey == key }.map { (p, $0) } }
                if schedules.isEmpty { Notice(text: "当日没有启用的安排。创建计划后，可指定训练日与休息日。") }
                ForEach(schedules, id: \.1.id) { p, d in
                    if d.rest { Label("休息日 · 无需完成任务", systemImage: "leaf") }
                    else { NavigationLink { WorkoutView(plan: p, day: d) } label: { VStack(alignment: .leading) { Text(p.name); Text("\(d.exercises.count) 个动作 · 查看清单与记录实际组数").font(.caption).foregroundStyle(.secondary) } } }
                }
            }
            Section("训练计划") {
                Button { editor = TrainingPlan() } label: { Label("手动创建计划", systemImage: "plus") }
                Button { aiSheet = true } label: { Label("AI / 演示计划草稿", systemImage: "sparkles") }
                ForEach(store.state.plans.sorted { ($0.days.first?.dayKey ?? "") > ($1.days.first?.dayKey ?? "") }) { p in
                    Button { editor = p } label: {
                        VStack(alignment: .leading) { Text(p.name).font(.headline); Text("\(p.active ? "已启用" : "草稿 / 停用") · \(p.days.count) 天\(p.demo ? " · 演示" : "")").font(.caption).foregroundStyle(.secondary) }
                    }.buttonStyle(.plain).swipeActions { Button("删除计划", role: .destructive) { do { try store.change { $0.plans.removeAll { $0.id == p.id } } } catch { self.error = error.localizedDescription } } }
                }
                Notice(text: "删除或修改计划不会删除、重写实际日志。同一日期只允许一个启用计划。")
            }
            Section("实际训练历史") {
                if store.state.workouts.isEmpty { Notice(text: "实际开始训练后，这里才会产生记录。计划本身不代表已训练。") }
                ForEach(store.state.workouts.sorted { $0.dayKey > $1.dayKey }) { log in
                    NavigationLink { WorkoutHistoryEditor(initial: log) } label: { VStack(alignment: .leading) { Text(log.dayKey); Text("\(log.finishedAt == nil ? "进行中" : "已结束") · \(log.exercises.filter { $0.status == "completed" }.count) 个完成动作").font(.caption).foregroundStyle(.secondary) } }
                }
            }
        }.navigationTitle("训练")
            .sheet(item: $editor) { PlanEditor(initial: $0) }
            .sheet(isPresented: $aiSheet) { AIPlanForm() }
            .fuelError($error)
    }
    private func hasTraining(_ key: String) -> Bool { store.state.plans.contains { $0.active && $0.days.contains { $0.dayKey == key && !$0.rest } } }
}
@MainActor struct PlanEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var plan: TrainingPlan
    @State private var start = Date()
    @State private var weeks = 1
    @State private var copySheet = false
    @State private var error: String?
    init(initial: TrainingPlan) { _plan = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            Form {
                Section("计划") { TextField("计划名称", text: $plan.name); if plan.demo { Notice(text: "演示计划草稿不会启用为个人训练，请核对强度、动作与器械。"); Button("已手动核对，转为个人计划草稿") { plan.demo = false } }; TextField("备注", text: $plan.notes, axis: .vertical) }
                Section("日期安排") {
                    ForEach($plan.days) { $day in
                        NavigationLink { PlanDayEditor(day: $day) } label: { HStack { Text(day.dayKey); Spacer(); Text(day.rest ? "休息" : "\(day.exercises.count) 个动作").foregroundStyle(.secondary) } }
                    }.onDelete { plan.days.remove(atOffsets: $0) }
                    Button("添加一天") { var d = PlanDay(); d.dayKey = plan.days.map(\.dayKey).max().map { DayKey.adding(1, to: $0) } ?? DayKey.make(start); d.rest = true; plan.days.append(d) }
                    if plan.days.isEmpty {
                        DatePicker("开始日期", selection: $start, displayedComponents: .date)
                        Button("建立一周（初始为休息日）") { for n in 0..<7 { var d = PlanDay(); d.dayKey = DayKey.adding(n, to: DayKey.make(start)); d.rest = true; plan.days.append(d) } }
                    }
                }
                if !plan.days.isEmpty { Section { Button("复制首周并安排多周") { copySheet = true }; Notice(text: "复制会建立新的独立计划草稿；历史训练日志不受影响。") } }
                Section {
                    Button("保存草稿 / 停用") { save(active: false) }
                    Button("确认并启用计划") { save(active: true) }.font(.headline).disabled(plan.demo)
                }
            }.navigationTitle("编辑训练计划")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .sheet(isPresented: $copySheet) {
                    NavigationStack { Form {
                        DatePicker("新计划开始", selection: $start, displayedComponents: .date)
                        Stepper("\(weeks) 周", value: $weeks, in: 1...12)
                        Button("保存为新草稿") { do { let copy = try plan.copyWeek(start: DayKey.make(start), weeks: weeks); try store.savePlan(copy); copySheet = false; dismiss() } catch { self.error = error.localizedDescription } }
                    }.navigationTitle("复制首周").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { copySheet = false } } } }
                }.fuelError($error)
        }
    }
    private func save(active: Bool) { do { plan.active = active; try store.savePlan(plan); dismiss() } catch { self.error = error.localizedDescription } }
}
@MainActor struct PlanDayEditor: View {
    @Environment(AppStore.self) private var store
    @Binding var day: PlanDay
    @State private var picker = false
    var body: some View {
        Form {
            DatePicker("日期", selection: Binding(get: { DayKey.date(day.dayKey) ?? Date() }, set: { day.dayKey = DayKey.make($0) }), displayedComponents: .date)
            Toggle("休息日", isOn: $day.rest).onChange(of: day.rest) { _, rest in if rest { day.exercises = [] } }
            if !day.rest {
                Section("动作清单") {
                    ForEach($day.exercises) { $exercise in NavigationLink { PlannedExerciseEditor(exercise: $exercise) } label: { VStack(alignment: .leading) { Text(exercise.name); Text("\(exercise.sets) 组 × \(exercise.minReps)–\(exercise.maxReps) 次").font(.caption).foregroundStyle(.secondary) } } }.onDelete { day.exercises.remove(atOffsets: $0) }
                    Button("从基础动作库添加") { picker = true }
                }
            } else { Notice(text: "休息日不会产生未完成任务。") }
        }.navigationTitle("日期安排")
            .sheet(isPresented: $picker) { ExercisePicker { e in var value = PlannedExercise(); value.exerciseID = e.id; value.name = e.name; day.exercises.append(value); picker = false } }
    }
}
@MainActor struct PlannedExerciseEditor: View {
    @Binding var exercise: PlannedExercise
    var body: some View {
        Form {
            Text(exercise.name).font(.headline)
            Stepper("\(exercise.sets) 组", value: $exercise.sets, in: 1...10)
            Stepper("最低 \(exercise.minReps) 次", value: $exercise.minReps, in: 1...100)
            Stepper("最高 \(exercise.maxReps) 次", value: $exercise.maxReps, in: 1...100)
            OptionalNumber(title: "目标重量 kg（可选）", value: $exercise.targetKG)
            Stepper("组间休息 \(exercise.restSeconds) 秒", value: $exercise.restSeconds, in: 15...600, step: 15)
            Notice(text: "这些是计划目标。实际重量、次数和完成状态在执行时单独记录。")
        }.navigationTitle("动作目标")
    }
}
@MainActor struct ExercisePicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var choose: (ExerciseDefinition) -> Void
    var body: some View {
        NavigationStack {
            List(store.exercises) { e in Button { choose(e) } label: { VStack(alignment: .leading, spacing: 4) { Text(e.name).font(.headline); Text(e.cue).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain) }
                .navigationTitle("基础动作库").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
