import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import ImageIO

@MainActor struct MealEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serviceURL") private var serviceURL = "http://localhost:8000"
    @State private var meal: Meal
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var error: String?
    @State private var analysisMessage: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var createdPaths: Set<String> = []
    @State private var reanalysisDraft: Meal?
    @State private var showRaw = false
    private let initiallyConfirmed: Bool
    init(initial: Meal) { _meal = State(initialValue: initial); initiallyConfirmed = initial.confirmed }
    var body: some View {
        NavigationStack {
            Form {
                Section(meal.isDemo ? "演示餐次（独立于个人统计）" : "个人餐次") {
                    DatePicker("时间（支持补录）", selection: $meal.occurredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: meal.occurredAt) { _, value in meal.dayKey = DayKey.make(value); meal.timeZoneID = TimeZone.current.identifier }
                    Picker("餐别", selection: $meal.kind) { ForEach(MealKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Text("归属日期：\(meal.dayKey)").font(.caption).foregroundStyle(.secondary)
                }
                Section("食物照片") {
                    if let path = meal.photoPath, let uiImage = PhotoFiles.image(path) {
                        Image(uiImage: uiImage).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("当前食物照片")
                    }
                    if initiallyConfirmed {
                        Notice(text: "已确认值不会被 AI 覆盖。再次分析将建立独立草稿，确认前请避免重复记录同一餐。")
                        if meal.photoPath != nil {
                            Button("从照片建立新的分析草稿") {
                                var copy = meal; copy.id = UUID(); copy.confirmed = false; copy.items = []; copy.rawAnalyses = []
                                reanalysisDraft = copy
                            }
                        }
                    } else {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("从相册选择", systemImage: "photo") }.disabled(busy)
                        Button { requestCamera() } label: { Label("拍摄食物", systemImage: "camera") }.disabled(busy)
                        if meal.photoPath != nil {
                            Button { analyze(demo: false) } label: { Label("发送照片到后端分析", systemImage: "sparkles") }.disabled(busy)
                            Button("本地演示分析（固定示例）") { analyze(demo: true) }.disabled(busy)
                            Notice(text: "仅在点击后端分析时上传照片。再次分析会替换当前草稿项目；已确认餐次不会自动覆盖。本地演示与图片内容无关，请手动核对。")
                        }
                    }
                    if busy { HStack { ProgressView(); Text("处理中…"); Spacer(); Button("取消") { task?.cancel(); requestID = UUID(); busy = false } } }
                    if let analysisMessage { Notice(text: analysisMessage) }
                }
                Section("食物项目 · \(meal.kcal.kcalText) kcal") {
                    ForEach($meal.items) { $item in
                        NavigationLink { FoodItemEditor(item: $item) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name.isEmpty ? "未命名食物（请编辑）" : item.name).font(.headline)
                                Text("\(item.consumed.kcal.kcalText) kcal · \(sourceLabel(item.source.kind))").font(.subheadline).foregroundStyle(.secondary)
                                if let grams = item.actualGrams { Text("供餐 \(item.servedGrams!.kcalText) g × \((item.eatenFraction * 100).kcalText)% = 实吃 \(grams.kcalText) g").font(.caption).foregroundStyle(.secondary) }
                                if !item.questions.isEmpty { Text(item.questions.joined(separator: "；")).font(.caption).foregroundStyle(.orange) }
                            }
                        }
                    }.onDelete { meal.items.remove(atOffsets: $0) }
                    Button("手动添加食物与热量") { meal.items.append(FoodItem()) }
                    Button("从常用食物库添加（按重量）") { showLibrary = true }
                    Button("录入整餐总热量") { var f = FoodItem(); f.name = "整餐总热量"; meal.items.append(f) }
                    Notice(text: "整餐总热量是一项独立记录，请勿再重复添加该餐内的食物。草稿可保存后继续编辑。")
                }
                Section("备注") { TextField("用油、份量或其他说明", text: $meal.notes, axis: .vertical) }
                if !meal.rawAnalyses.isEmpty {
                    Section { DisclosureGroup("查看保留的 AI 原始草稿", isExpanded: $showRaw) { ForEach(Array(meal.rawAnalyses.enumerated()), id: \.offset) { _, raw in Text(raw).font(.caption.monospaced()).textSelection(.enabled) } } }
                }
                Section {
                    if meal.isDemo && !initiallyConfirmed {
                        Notice(text: "演示数据单独分区，不计入个人摄入。只有你确认名称、份量和热量代表自己的实际一餐后，才可转为个人草稿。")
                        Button("已手动核对，转为个人草稿") { meal.isDemo = false }
                    }
                    if !initiallyConfirmed { Button("保存草稿（不计入摄入）") { save(confirmed: false) }.disabled(busy) }
                    Button(initiallyConfirmed ? "保存修改" : (meal.isDemo ? "确认演示（不计入个人摄入）" : "确认并计入摄入")) { save(confirmed: true) }.font(.headline).disabled(busy || meal.items.isEmpty)
                }
            }.navigationTitle(initiallyConfirmed ? "编辑餐次" : "记一餐")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .sheet(isPresented: $showCamera) { CameraCapture { image in showCamera = false; if let image { installPhoto(image) } } }
                .sheet(isPresented: $showLibrary) { FoodLibrary { meal.items.append($0.item()); showLibrary = false } }
                .sheet(item: $reanalysisDraft) { MealEditor(initial: $0) }
                .onChange(of: selectedPhoto) { _, value in loadPhoto(value) }
                .fuelError($error)
        }.onDisappear { task?.cancel(); cleanup() }
    }
    private func sourceLabel(_ kind: String) -> String { ["manual":"手动录入", "database":"数据库匹配", "ai":"AI 估算", "demo":"演示估算"][kind] ?? kind }
    private func save(confirmed: Bool) {
        do { meal.confirmed = confirmed; try store.saveMeal(meal); dismiss() } catch { self.error = error.localizedDescription }
    }
    private func installPhoto(_ image: UIImage) {
        do { let path = try PhotoFiles.save(image); createdPaths.insert(path); meal.photoPath = path; analysisMessage = "照片已在 App 持久目录保存，可分析或手动添加食物。" } catch { self.error = error.localizedDescription }
    }
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }; task?.cancel(); busy = true; let job = UUID(); requestID = job
        task = Task { @MainActor in
            defer { if requestID == job { busy = false } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= 40 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { throw DomainError.invalid("无法读取照片或原图过大，请选择其他照片；相册选择只授权你选中的图片") }
                try Task.checkCancellation(); installPhoto(UIImage(cgImage: thumbnail))
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = "此设备没有可用相机；模拟器请从相册选择图片"; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized { showCamera = true }
        else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in Task { @MainActor in if granted { showCamera = true } else { error = "相机权限被拒绝，可在系统设置中开启或从相册选择" } } }
        } else { error = "相机权限被拒绝，可在系统设置中开启或从相册选择" }
    }
    private func analyze(demo: Bool) {
        guard !busy, !initiallyConfirmed, let path = meal.photoPath else { return }; busy = true; let job = UUID(); requestID = job
        task = Task { @MainActor in
            defer { if requestID == job { busy = false } }
            do {
                let response: AnalysisResponse
                if demo {
                    guard let rice = store.foods.first(where: { $0.id == "rice-cooked" }) else { throw DomainError.invalid("离线库缺少演示条目") }
                    var f = rice.item(); f.servedGrams = 150
                    let suggested = SuggestedFood(name: f.name, servedGrams: 150, preparation: f.preparation, basis: f.basis, nutrients: f.nutrients, source: f.source, assumptions: ["固定示例，与照片无关"], questions: ["请核对份量、用油、酱料和剩余量"])
                    response = AnalysisResponse(mode: "mock", isFood: true, items: [suggested], message: "本地演示分析", warnings: ["固定米饭示例，不是真实识别"], catalogVersion: "fuelform-foods-1.0.0")
                } else {
                    let client = try APIClient(address: serviceURL, token: ServiceKeychain.read())
                    response = try await client.analyze(jpeg: Data(contentsOf: PhotoFiles.url(path)))
                }
                try Task.checkCancellation()
                let foods = try response.validatedItems()
                meal.isDemo = response.mode == "mock"
                meal.rawAnalyses.append(String(decoding: try JSONCoding.encoder().encode(response), as: UTF8.self))
                analysisMessage = ([response.mode == "mock" ? "演示分析" : "AI 分析草稿", response.message] + response.warnings).joined(separator: "\n")
                if response.isFood { meal.items = foods } else { error = "未识别到食物：\(response.message)。可更换照片或手动录入。" }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func cleanup() {
        let used = Set(store.state.meals.compactMap(\.photoPath))
        for path in createdPaths.subtracting(used) { try? PhotoFiles.remove(path) }
    }
}
@MainActor struct FoodItemEditor: View {
    @Binding var item: FoodItem
    var body: some View {
        Form {
            Section("名称与份量") {
                TextField("食物名称", text: $item.name)
                TextField("烹饪方式 / 生重熟重", text: $item.preparation)
                OptionalNumber(title: "供餐重量 g", value: $item.servedGrams)
                Slider(value: $item.eatenFraction, in: 0...1, step: 0.01) { Text("食用比例") }.accessibilityLabel("食用比例")
                Text("吃下 \((item.eatenFraction * 100).kcalText)% · \(item.actualGrams.map { $0.kcalText + " g" } ?? "重量未知")")
                Notice(text: "供餐重量填写上桌时的可食重量，比例填写实际吃下的部分。不要先扣剩余重量又降低比例。")
            }
            Section(item.basis == "per100" ? "每 100 g 营养值" : "整份供餐的营养值") {
                NumberRow(title: "热量 kcal", value: $item.nutrients.kcal)
                OptionalNumber(title: "蛋白质 g", value: $item.nutrients.protein)
                OptionalNumber(title: "碳水 g", value: $item.nutrients.carbs)
                OptionalNumber(title: "脂肪 g", value: $item.nutrients.fat)
                Text("实际计入 \(item.consumed.kcal.kcalText) kcal").font(.headline)
                if item.basis == "total" { Notice(text: "按整份营养 × 食用比例计算；供餐重量可留空，重量变化不会自动改变整份热量。") }
            }
            Section("营养来源与待核对信息") {
                Text(item.source.label).font(.footnote)
                Text("版本：\(item.source.version)").font(.caption)
                if let reference = item.source.reference, let url = URL(string: reference) { Link("查看原始数据来源", destination: url) }
                ForEach(item.assumptions, id: \.self) { Notice(text: $0) }
                ForEach(item.questions, id: \.self) { Notice(text: $0, symbol: "questionmark.circle") }
            }
        }.navigationTitle("编辑食物")
            .onChange(of: item.nutrients) { _, _ in markEdited() }
            .onChange(of: item.name) { _, _ in markEdited() }
            .onChange(of: item.preparation) { _, _ in markEdited() }
    }
    private func markEdited() {
        if item.source.kind != "manual" { item.source.kind = "manual"; item.source.label = "手动修订 · 原来源：" + item.source.label }
    }
}
@MainActor struct FoodLibrary: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var choose: (FoodDefinition) -> Void
    var body: some View {
        NavigationStack {
            List(store.foods.filter { search.isEmpty || $0.name.contains(search) || $0.aliases.contains(where: { $0.contains(search) }) }) { f in
                Button { choose(f) } label: { VStack(alignment: .leading, spacing: 4) { Text(f.name).font(.headline); Text("\(f.nutrients.kcal.kcalText) kcal / 100 g · \(f.preparation)").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
            }.navigationTitle("常用食物").searchable(text: $search, prompt: "搜索食物")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
@MainActor struct CameraCapture: UIViewControllerRepresentable {
    var result: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(result: result) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let result: (UIImage?) -> Void
        init(result: @escaping (UIImage?) -> Void) { self.result = result }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { result(info[.originalImage] as? UIImage) }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { result(nil) }
    }
}
