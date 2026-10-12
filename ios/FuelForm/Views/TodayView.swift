import Combine
import SwiftUI

@MainActor struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = DayKey.make(Date())
    @State private var editor: Meal?
    @State private var error: String?
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private var meals: [Meal] {
        store.state.meals.filter { $0.dayKey == today && !$0.isDemo }.sorted { $0.occurredAt < $1.occurredAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("今天的饮食", systemImage: "sun.max.fill").font(.headline).foregroundStyle(.teal)
                        Spacer()
                        NavigationLink { ProfileView() } label: { Image(systemName: "slider.horizontal.3").padding(8) }.accessibilityLabel("设置热量目标与消耗估算")
                    }
                    SummaryView(summary: store.state.summary(today), snapshot: store.state.days.first { $0.dayKey == today })
                    Button { newMeal() } label: {
                        Label("记一餐", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    if store.state.days.first(where: { $0.dayKey == today })?.intakeTarget == nil {
                        NavigationLink { ProfileView() } label: { Label("设置每日目标", systemImage: "arrow.right.circle").font(.subheadline) }
                    }
                }.fuelCard()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("今日餐次").font(.title2.bold())
                        Spacer()
                        NavigationLink("查看记录") { MealsView() }.font(.subheadline)
                    }
                    ForEach(MealKind.allCases, id: \.self) { kind in
                        mealSection(kind)
                    }
                }
                trainingSection
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("FuelForm")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Text(DayKey.date(today)?.formatted(.dateTime.month().day().weekday()) ?? today).font(.caption).foregroundStyle(.secondary) } }
        .sheet(item: $editor) { MealEditor(initial: $0) }
        .onAppear { refresh() }.onReceive(ticker) { _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .fuelError($error)
    }
    private func mealSection(_ kind: MealKind) -> some View {
        let entries = meals.filter { $0.kind == kind }
        let confirmed = entries.filter(\.confirmed)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(kind.rawValue, systemImage: kind.symbol).font(.headline)
                Spacer()
                if !confirmed.isEmpty { Text("\(confirmed.reduce(0) { $0 + $1.kcal }.kcalText) kcal").font(.subheadline).monospacedDigit() }
                Button { newMeal(kind) } label: { Image(systemName: "plus.circle.fill").font(.title2).padding(4) }.accessibilityLabel("添加\(kind.rawValue)")
            }
            if entries.isEmpty {
                Text("尚未记录").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(entries) { meal in
                    Button { editor = meal } label: { MealRow(meal: meal) }.buttonStyle(.plain)
                }
            }
        }.fuelCard()
    }
    private var trainingSection: some View {
        let schedules = store.state.plans.filter(\.active).flatMap { p in p.days.filter { $0.dayKey == today }.map { (p, $0) } }
        return VStack(alignment: .leading, spacing: 14) {
            Label("今日训练", systemImage: "dumbbell.fill").font(.title2.bold())
            if schedules.isEmpty {
                Text("今天还没有训练安排").font(.headline)
                Text("安排训练日与休息日，按自己的节奏开始。") .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(schedules, id: \.1.id) { plan, day in
                if day.rest { Label("休息日 · 好好恢复", systemImage: "leaf").foregroundStyle(.teal) }
                else {
                    let log = store.state.workouts.first { $0.planDayID == day.id && $0.dayKey == today }
                    NavigationLink { WorkoutView(plan: plan, day: day) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.name).font(.headline)
                            Label(log?.finishedAt != nil ? "已完成 · 查看记录" : (log == nil ? "\(day.exercises.count) 个动作 · 开始训练" : "继续训练"), systemImage: log?.finishedAt != nil ? "checkmark.circle" : "play.circle")
                        }
                    }
                }
            }
            NavigationLink(schedules.isEmpty ? "建立训练计划" : "管理训练计划") { TrainingView() }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, alignment: .leading).fuelCard()
    }
    private func newMeal(_ kind: MealKind? = nil) {
        var meal = Meal(); meal.dayKey = today
        if let kind { meal.kind = kind }
        editor = meal
    }
    private func refresh() {
        today = DayKey.make(Date())
        if !store.state.days.contains(where: { $0.dayKey == today }) { do { try store.change { $0.ensureDay(today) } } catch { self.error = error.localizedDescription } }
    }
}
