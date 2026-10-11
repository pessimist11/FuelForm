import SwiftUI

@MainActor struct WorkoutView: View {
    @Environment(AppStore.self) private var store
    let plan: TrainingPlan
    let day: PlanDay
    @State private var error: String?
    var body: some View {
        Group {
            if let log = store.state.workouts.first(where: { $0.planDayID == day.id && $0.dayKey == day.dayKey }) {
                WorkoutHistoryEditor(initial: log)
            } else {
                List {
                    Section(day.dayKey) { ForEach(day.exercises) { e in VStack(alignment: .leading) { Text(e.name).font(.headline); Text("\(e.sets) 组 × \(e.minReps)–\(e.maxReps) 次 · 休息 \(e.restSeconds) 秒").font(.subheadline).foregroundStyle(.secondary) } } }
                    Section {
                        if day.dayKey > DayKey.make(Date()) { Notice(text: "未来日期的计划不能标记为已训练。可在计划编辑器调整日期。") }
                        else { Button("开始训练并建立实际日志") { do { _ = try store.startWorkout(plan, day) } catch { self.error = error.localizedDescription } }.font(.headline) }
                        Notice(text: "开始后保存独立动作快照，之后编辑计划不会改写此日志。")
                    }
                }.navigationTitle("训练清单")
            }
        }.fuelError($error)
    }
}
@MainActor struct WorkoutHistoryEditor: View {
    @Environment(AppStore.self) private var store
    @State private var log: WorkoutLog
    @State private var error: String?
    @State private var replaceID: UUID?
    @State private var showReplace = false
    @State private var restEnd: Date?
    @State private var saveStatus = "修改后自动保存到本机"
    init(initial: WorkoutLog) { _log = State(initialValue: initial) }
    var body: some View {
        Form {
            Section { Text(log.dayKey).font(.headline); Text(saveStatus).font(.caption).foregroundStyle(.secondary) }
            if let end = restEnd, end > Date() {
                Section("组间休息") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in Text("\(max(0, Int(end.timeIntervalSince(context.date)))) 秒").font(.title.monospacedDigit()) }
                    Button("结束休息") { restEnd = nil }
                }
            }
            ForEach($log.exercises) { $exercise in
                Section {
                    Text(exercise.actualName).font(.headline)
                    Notice(text: "原计划：\(exercise.planned.name)，\(exercise.planned.sets) 组 × \(exercise.planned.minReps)–\(exercise.planned.maxReps) 次")
                    Picker("动作状态", selection: $exercise.status) {
                        Text("待完成").tag("pending"); Text("已完成").tag("completed"); Text("跳过").tag("skipped")
                    }
                    if exercise.status != "skipped" {
                        ForEach(Array(exercise.sets.indices), id: \.self) { index in
                            VStack(alignment: .leading) {
                                Text("第 \(index + 1) 组").font(.subheadline.weight(.semibold))
                                HStack { Text("次数"); TextField("次数", value: $exercise.sets[index].reps, format: .number).keyboardType(.numberPad).accessibilityLabel("第\(index + 1)组次数"); Text("重量 kg"); TextField("kg", value: $exercise.sets[index].kg, format: .number).keyboardType(.decimalPad).accessibilityLabel("第\(index + 1)组重量千克") }
                                Toggle("该组完成", isOn: $exercise.sets[index].completed)
                            }.padding(.vertical, 4)
                        }
                        Button("增加实际组") { exercise.sets.append(SetLog()) }.disabled(exercise.sets.count >= 20)
                        if !exercise.sets.isEmpty { Button("删除末组") { exercise.sets.removeLast() } }
                        Button("休息 \(exercise.planned.restSeconds) 秒") { restEnd = Date().addingTimeInterval(Double(exercise.planned.restSeconds)) }
                    }
                    Button("替换本次实际动作") { replaceID = exercise.id; showReplace = true }
                    TextField("实际动作名称（可编辑）", text: $exercise.actualName)
                }
            }
            Section("训练备注") { TextField("感受、调整和备注", text: $log.notes, axis: .vertical) }
            Section {
                Button("保存进度") { persist() }
                if log.finishedAt != nil { Text("已结束 · \(log.finishedAt!.formatted(date: .abbreviated, time: .shortened))"); Button("重新打开日志") { log.finishedAt = nil } }
                else { Button("结束本次训练") { finish() }.font(.headline) }
                Notice(text: "实际组数可与计划不同。跳过动作会保留原目标和已填写的组记录。训练不自动换算为热量。")
            }
        }.navigationTitle("实际训练")
            .sheet(isPresented: $showReplace) { ExercisePicker { e in if let index = log.exercises.firstIndex(where: { $0.id == replaceID }) { log.exercises[index].actualName = e.name; log.exercises[index].actualExerciseID = e.id }; showReplace = false } }
            .onChange(of: log) { _, _ in persist() }
            .fuelError($error)
    }
    private func persist() {
        do { try store.saveWorkout(log); saveStatus = "已保存到本机" } catch { saveStatus = "保存失败，修改仍在当前页面"; self.error = error.localizedDescription }
    }
    private func finish() {
        guard log.exercises.allSatisfy({ $0.status != "pending" }) else { error = "请将每个动作标为完成或跳过"; return }
        guard log.exercises.filter({ $0.status == "completed" }).allSatisfy({ !$0.sets.isEmpty && $0.sets.allSatisfy { $0.completed && $0.reps > 0 } }) else { error = "完成动作需要至少一组，并填写次数和勾选各组完成"; return }
        log.finishedAt = Date()
    }
}
