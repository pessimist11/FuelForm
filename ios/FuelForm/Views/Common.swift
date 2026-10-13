import SwiftUI
import UIKit

@MainActor final class KeyboardDismissalController: ObservableObject {
    weak var anchor: UIView?
    func dismiss() { anchor?.window?.endEditing(true) }
}

private struct KeyboardDismissalAnchor: UIViewRepresentable {
    let controller: KeyboardDismissalController
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        controller.anchor = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { controller.anchor = uiView }
}

private struct KeyboardDismissalModifier: ViewModifier {
    @StateObject private var controller = KeyboardDismissalController()
    func body(content: Content) -> some View {
        content
            .background(KeyboardDismissalAnchor(controller: controller).allowsHitTesting(false))
            .scrollDismissesKeyboard(.interactively)
            .onSubmit { controller.dismiss() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("收起键盘", systemImage: "keyboard.chevron.compact.down") { controller.dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("dismissKeyboard")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { controller.dismiss() }
                }
            }
    }
}

extension View {
    func fuelKeyboardDismissal() -> some View { modifier(KeyboardDismissalModifier()) }
}

extension Double { var kcalText: String { formatted(.number.precision(.fractionLength(0))) } }
@MainActor struct Notice: View {
    var text: String
    var symbol: String = "info.circle"
    var body: some View { Label(text, systemImage: symbol).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
@MainActor struct OptionalNumber: View {
    var title: String
    @Binding var value: Double?
    var focus: FocusState<Bool>.Binding? = nil
    var body: some View {
        HStack {
            Text(title)
            if let focus { field.focused(focus) } else { field }
        }
    }
    private var field: some View {
        TextField("未填写", value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(title)
    }
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
extension MealKind {
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "carrot"
        }
    }
}
extension View {
    func fuelCard() -> some View {
        padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
@MainActor struct SummaryView: View {
    var summary: DaySummary
    var snapshot: DaySnapshot?
    @State private var showEstimate = false
    private var known: Bool { summary.hasRecords || snapshot?.complete == true }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(summary.status).font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { intake; remaining }
                VStack(alignment: .leading, spacing: 16) { intake; remaining }
            }
            if let target = snapshot?.intakeTarget {
                VStack(alignment: .leading, spacing: 6) {
                    if known { ProgressView(value: min(summary.intake, target), total: max(1, target)).tint(summary.intake > target ? .orange : .teal).accessibilityLabel("摄入目标进度") }
                    Text("每日目标 \(target.kcalText) kcal").font(.subheadline).foregroundStyle(.secondary)
                }
            } else { Text("设置目标后，查看今天的剩余额度").font(.subheadline).foregroundStyle(.secondary) }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) { expenditure; deficit }
                VStack(alignment: .leading, spacing: 12) { expenditure; deficit }
            }
            DisclosureGroup("这些数字怎么算？", isExpanded: $showEstimate) {
                Text("剩余额度 = 摄入目标 − 已记录摄入。估算缺口 = 估算总消耗 − 已记录摄入。消耗由你设置，计划训练不会额外计入。未记全时仅表示截至目前的记录。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.caption)
        }
    }
    private var intake: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("已记录摄入").font(.subheadline).foregroundStyle(.secondary)
            Text(known ? summary.intake.kcalText : "—").font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
            Text("kcal").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var remaining: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((summary.remaining ?? 0) < 0 ? "超过摄入目标" : "剩余饮食额度").font(.subheadline).foregroundStyle(.secondary)
            Text(summary.remaining.map { abs($0).kcalText } ?? "—").font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle((summary.remaining ?? 0) < 0 ? Color.orange : Color.teal)
            Text("kcal").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var expenditure: some View { metric("估算总消耗", snapshot?.expenditure) }
    private var deficit: some View { metric((summary.deficit ?? 0) < 0 ? "估算热量盈余" : "估算热量缺口", summary.deficit) }
    private func metric(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map { abs($0).kcalText + " kcal" } ?? "—").font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
