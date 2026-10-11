import Combine
import SwiftUI

@MainActor struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = DayKey.make(Date())
    @State private var editor: Meal?
    @State private var error: String?
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        List {
            Section { SummaryView(summary: store.state.summary(today), snapshot: store.state.days.first { $0.dayKey == today }) }
            Section {
                Button { var m = Meal(); m.dayKey = today; editor = m } label: { Label("记一餐", systemImage: "plus.circle.fill").font(.headline).padding(.vertical, 6) }
            }
            Section("当天餐次") {
                let meals = store.state.meals.filter { $0.dayKey == today && !$0.isDemo }.sorted { $0.occurredAt < $1.occurredAt }
                if meals.isEmpty { Notice(text: "还没有记录。拍照估算或手动录入均可，草稿确认后才计入摄入。", symbol: "fork.knife") }
                ForEach(meals) { m in Button { editor = m } label: { MealRow(meal: m) }.buttonStyle(.plain) }
            }
            Section("今日训练") {
                let schedules = store.state.plans.filter(\.active).flatMap { p in p.days.filter { $0.dayKey == today }.map { (p, $0) } }
                if schedules.isEmpty { Notice(text: "没有安排训练。可在训练页建立一周或多周计划。", symbol: "dumbbell") }
                ForEach(schedules, id: \.1.id) { plan, day in
                    if day.rest { Label("休息日", systemImage: "leaf"); Notice(text: "休息是计划的一部分，无需打卡。") }
                    else { NavigationLink { WorkoutView(plan: plan, day: day) } label: { Label("\(day.exercises.count) 个动作 · 开始或继续", systemImage: "play.circle") } }
                }
            }
        }.navigationTitle("FuelForm")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Text(today).font(.caption).foregroundStyle(.secondary) } }
            .sheet(item: $editor) { MealEditor(initial: $0) }
            .onAppear { refresh() }.onReceive(ticker) { _ in refresh() }.onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .fuelError($error)
    }
    private func refresh() {
        today = DayKey.make(Date())
        if !store.state.days.contains(where: { $0.dayKey == today }) { do { try store.change { $0.ensureDay(today) } } catch { self.error = error.localizedDescription } }
    }
}
