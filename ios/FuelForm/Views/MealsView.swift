import SwiftUI

@MainActor struct MealsView: View {
    @Environment(AppStore.self) private var store
    @State private var date = Date()
    @State private var editor: Meal?
    @State private var error: String?
    @State private var confirmComplete = false
    @State private var targetEditor = false
    var key: String { DayKey.make(date) }
    var body: some View {
        List {
            Section { DatePicker("记录日期", selection: $date, in: ...Date(), displayedComponents: .date) }
            Section {
                SummaryView(summary: store.state.summary(key), snapshot: store.state.days.first { $0.dayKey == key })
                Button("编辑当天目标与消耗快照") { targetEditor = true }
                if let day = store.state.days.first(where: { $0.dayKey == key }), day.complete {
                    Button("撤销记全标记") { markComplete(false) }
                } else { Button("确认当天已记全") { confirmComplete = true } }
            }
            ForEach(MealKind.allCases, id: \.self) { kind in
                Section {
                    let meals = store.state.meals.filter { $0.dayKey == key && !$0.isDemo && $0.kind == kind }.sorted { $0.occurredAt < $1.occurredAt }
                    if meals.isEmpty { Text("尚未记录").foregroundStyle(.secondary) }
                    ForEach(meals) { m in
                        Button { editor = m } label: { MealRow(meal: m) }.buttonStyle(.plain)
                            .swipeActions { Button("删除", role: .destructive) { do { try store.deleteMeal(m.id) } catch { self.error = error.localizedDescription } } }
                    }
                    Button { newMeal(kind) } label: { Label("添加\(kind.rawValue)", systemImage: "plus") }
                } header: { Label(kind.rawValue, systemImage: kind.symbol) }
            }
            let demoMeals = store.state.meals.filter { $0.dayKey == key && $0.isDemo }
            if !demoMeals.isEmpty {
                Section("演示餐次 · 不计入个人统计") {
                    ForEach(demoMeals) { m in
                        Button { editor = m } label: { MealRow(meal: m) }.buttonStyle(.plain)
                            .swipeActions { Button("删除演示", role: .destructive) { do { try store.deleteMeal(m.id) } catch { self.error = error.localizedDescription } } }
                    }
                }
            }
        }.navigationTitle("饮食")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { newMeal(.lunch) } label: { Label("记一餐", systemImage: "plus") } } }
            .sheet(item: $editor) { MealEditor(initial: $0) }
            .sheet(isPresented: $targetEditor) { DayTargetEditor(dayKey: key) }
            .alert("确认已完整记录当天摄入？", isPresented: $confirmComplete) {
                Button("确认已记全") { markComplete(true) }; Button("取消", role: .cancel) {}
            } message: { Text("请包含饮料、零食等。今天尚未结束时仍显示截至目前；没有餐次也可以明确确认摄入为零。") }
            .fuelError($error)
    }
    private func newMeal(_ kind: MealKind) {
        var meal = Meal(); meal.occurredAt = min(date, Date()); meal.dayKey = key; meal.kind = kind; editor = meal
    }
    private func markComplete(_ complete: Bool) {
        do { try store.change { $0.ensureDay(key); if let i = $0.days.firstIndex(where: { $0.dayKey == key }) { $0.days[i].complete = complete } } } catch { self.error = error.localizedDescription }
    }
}
@MainActor struct DayTargetEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var dayKey: String
    @FocusState private var inputFocused: Bool
    @State private var target: Double?
    @State private var expenditure: Double?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(dayKey) { OptionalNumber(title: "摄入目标 kcal", value: $target, focus: $inputFocused); OptionalNumber(title: "估算总消耗 kcal", value: $expenditure, focus: $inputFocused) }
                Notice(text: "这是对该日期快照的明确修改，不会改动其他日期。补录日期首次创建快照时采用当前设置，请核对当日实际使用的目标。")
            }.navigationTitle("当天快照")
                .onAppear { if let day = store.state.days.first(where: { $0.dayKey == dayKey }) { target = day.intakeTarget; expenditure = day.expenditure } else { target = store.state.profile.intakeTarget; expenditure = store.state.profile.expenditure } }
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { inputFocused = false } }
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        inputFocused = false
                        do {
                            var p = Profile(); p.intakeTarget = target; p.expenditure = expenditure; try p.validate()
                            try store.change { $0.ensureDay(dayKey); if let i = $0.days.firstIndex(where: { $0.dayKey == dayKey }) { $0.days[i].intakeTarget = target; $0.days[i].expenditure = expenditure } }; dismiss()
                        } catch { self.error = error.localizedDescription }
                    } }
                }.fuelError($error)
        }
    }
}
