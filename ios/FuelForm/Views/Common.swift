import SwiftUI

extension Double { var kcalText: String { formatted(.number.precision(.fractionLength(0))) } }
@MainActor struct Notice: View {
    var text: String
    var symbol: String = "info.circle"
    var body: some View { Label(text, systemImage: symbol).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
@MainActor struct OptionalNumber: View {
    var title: String
    @Binding var value: Double?
    var body: some View { HStack { Text(title); TextField("未填写", value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(title) } }
}
@MainActor struct NumberRow: View {
    var title: String
    @Binding var value: Double
    var body: some View { HStack { Text(title); TextField(title, value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(title) } }
}
@MainActor struct ErrorAlert: ViewModifier {
    @Binding var error: String?
    func body(content: Content) -> some View {
        content.alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
extension View { func fuelError(_ error: Binding<String?>) -> some View { modifier(ErrorAlert(error: error)) } }
@MainActor struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayView() }.tabItem { Label("今日", systemImage: "sun.max") }
            NavigationStack { MealsView() }.tabItem { Label("饮食", systemImage: "fork.knife") }
            NavigationStack { TrainingView() }.tabItem { Label("训练", systemImage: "dumbbell") }
            NavigationStack { ProfileView() }.tabItem { Label("我的", systemImage: "person.crop.circle") }
        }.tint(.teal)
    }
}
@MainActor struct MealRow: View {
    var meal: Meal
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: meal.confirmed ? "fork.knife.circle.fill" : "pencil.circle").foregroundStyle(meal.confirmed ? .teal : .orange).font(.title2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.kind.rawValue + (meal.isDemo ? " · 演示" : "")).font(.headline)
                Text(meal.items.map(\.name).joined(separator: "、")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if meal.rawAnalyses.contains(where: { $0.contains("\"mock\"") }) { Text("含演示分析，请核对").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            VStack(alignment: .trailing) { Text("\(meal.kcal.kcalText) kcal").monospacedDigit(); if meal.isDemo { Text("演示 · 不计入").font(.caption).foregroundStyle(.orange) }; if !meal.confirmed { Text("草稿 · 未计入").font(.caption).foregroundStyle(.orange) } }
        }.padding(.vertical, 4)
    }
}
@MainActor struct SummaryView: View {
    var summary: DaySummary
    var snapshot: DaySnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.status).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(summary.hasRecords || snapshot?.complete == true ? summary.intake.kcalText : "—").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                Text("kcal 已记录摄入").font(.subheadline).foregroundStyle(.secondary)
            }
            if let target = snapshot?.intakeTarget {
                ProgressView(value: min(summary.intake, target), total: max(1, target)).tint(.teal).accessibilityLabel("摄入目标进度")
                Text("摄入目标 \(target.kcalText) kcal").font(.caption).foregroundStyle(.secondary)
            } else { Text("摄入目标未设置").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .top, spacing: 20) {
                metric(summary.remaining.map { $0 < 0 ? "超过摄入目标" : "剩余饮食额度" } ?? "剩余饮食额度", summary.remaining)
                metric(summary.deficit.map { $0 < 0 ? "估算热量盈余" : "估算热量缺口" } ?? "估算热量缺口", summary.deficit)
            }
            Notice(text: "消耗估算 \(snapshot?.expenditure.map { $0.kcalText + " kcal" } ?? "未设置")；计划训练不计入消耗。未记全的日期仅显示已记录摄入与估算值。")
        }.padding(.vertical, 6)
    }
    private func metric(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map { abs($0).kcalText + " kcal" } ?? "—").font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
