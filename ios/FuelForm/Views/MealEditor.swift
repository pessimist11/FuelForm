import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import ImageIO

@MainActor struct MealEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
    @State private var showPhoto = false
    @State private var showDiscard = false
    @FocusState private var focusedFood: UUID?
    private let original: Meal
    private let initiallyConfirmed: Bool
    init(initial: Meal) {
        _meal = State(initialValue: initial); original = initial; initiallyConfirmed = initial.confirmed
        _showPhoto = State(initialValue: initial.photoPath != nil)
    }
    private var dirty: Bool { meal != original }
    private var canSave: Bool { (try? meal.validate()) != nil && !busy }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("餐别", selection: $meal.kind) { ForEach(MealKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("记录时间")
                            datePicker.labelsHidden().dynamicTypeSize(...DynamicTypeSize.large)
                        }
                    } else { datePicker }
                }
                if meal.items.isEmpty && meal.photoPath == nil && !showPhoto {
                    Section {
                        entryButton("拍照 / 相册", subtitle: "选一张食物照片，获取可编辑的估算", symbol: "camera.fill") { showPhoto = true }
                        entryButton("搜索食物", subtitle: "从常用食物库选择，按重量记录", symbol: "magnifyingglass") { showLibrary = true }
                        entryButton("快速输入热量", subtitle: "知道热量时，直接记下这一餐", symbol: "square.and.pencil") { addManual() }
                    } header: { Text("这餐怎么记录？") } footer: { Text("手动录入和食物库无需联网。只有确认后的餐次才计入摄入。") }
                }
                if showPhoto || meal.photoPath != nil { photoSection }
                ForEach($meal.items) { $item in
                    Section {
                        MealDraftItem(item: $item, focus: $focusedFood)
                        Button("移除此食物", role: .destructive) { meal.items.removeAll { $0.id == item.id } }
                    }
                }
                if !meal.items.isEmpty || meal.photoPath != nil || showPhoto {
                    Section {
                        Menu {
                            Button("手动输入名称与热量", systemImage: "square.and.pencil") { addManual() }
                            Button("搜索食物库", systemImage: "magnifyingglass") { showLibrary = true }
                            if !initiallyConfirmed { Button("拍照 / 相册", systemImage: "camera") { showPhoto = true } }
                        } label: { Label("添加食物", systemImage: "plus.circle.fill") }
                    } footer: { Text("如果已录入整餐总热量，请勿重复添加这餐里的食物。") }
                    Section {
                        TextField("用油、份量或其他备注（可选）", text: $meal.notes, axis: .vertical)
                        if !meal.rawAnalyses.isEmpty {
                            NavigationLink("分析详情与原始记录") { analysisDetails }
                        }
                    }
                }
                if meal.isDemo {
                    Section {
                        Notice(text: "演示分析 · 与照片内容无关，不计入个人摄入。")
                        if !initiallyConfirmed { Button("已核对实物，转为个人草稿") { meal.isDemo = false } }
                    }
                }
            }
            .navigationTitle(initiallyConfirmed ? "编辑餐次" : "记一餐")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !meal.items.isEmpty || meal.photoPath != nil { confirmationBar.dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
            }
            .fuelKeyboardDismissal()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { if dirty || busy { showDiscard = true } else { dismiss() } } }
            }
            .confirmationDialog("保留这次修改？", isPresented: $showDiscard, titleVisibility: .visible) {
                if canSave { Button(initiallyConfirmed ? "保存修改" : "保存为草稿") { save(confirmed: initiallyConfirmed) } }
                Button("放弃修改", role: .destructive) { task?.cancel(); cleanup(); dismiss() }
                Button("继续编辑", role: .cancel) {}
            } message: { Text("未保存的修改会丢失，之前保存的记录不受影响。") }
            .sheet(isPresented: $showCamera) { CameraCapture { image in showCamera = false; if let image { installPhoto(image) } } }
            .sheet(isPresented: $showLibrary) { FoodLibrary { meal.items.append($0.item()); showLibrary = false } }
            .sheet(item: $reanalysisDraft) { MealEditor(initial: $0) }
            .onChange(of: selectedPhoto) { _, value in loadPhoto(value) }
            .fuelError($error)
        }.interactiveDismissDisabled(dirty || busy).onDisappear { task?.cancel() }
    }
    private var datePicker: some View {
        DatePicker("记录时间", selection: $meal.occurredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            .onChange(of: meal.occurredAt) { _, value in meal.dayKey = DayKey.make(value); meal.timeZoneID = TimeZone.current.identifier }
    }
    private func entryButton(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title2).frame(width: 36).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(.vertical, 10)
        }.buttonStyle(.plain)
    }
    private func addManual() {
        var item = FoodItem(); item.name = meal.items.isEmpty ? "整餐总热量" : ""
        meal.items.append(item)
    }
    private var photoSection: some View {
        Section("食物照片") {
            if let path = meal.photoPath, let uiImage = PhotoFiles.image(path) {
                Image(uiImage: uiImage).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel("当前食物照片")
            }
            if initiallyConfirmed {
                Button("从照片建立新的分析草稿") {
                    var copy = meal; copy.id = UUID(); copy.confirmed = false; copy.items = []; copy.rawAnalyses = []
                    reanalysisDraft = copy
                }
                Notice(text: "新草稿不会改动这条记录，请避免重复确认同一餐。")
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("从相册选择", systemImage: "photo") }.disabled(busy)
                Button { requestCamera() } label: { Label("拍摄食物", systemImage: "camera") }.disabled(busy)
                if meal.photoPath != nil {
                    Button { analyze(demo: false) } label: { Label("分析这张照片", systemImage: "sparkles") }.disabled(busy)
                    Notice(text: "点击分析才会上传照片。分析结果可修改，确认后才计入摄入。")
                    DisclosureGroup("试用演示") {
                        Button("使用固定示例（非真实识别）") { analyze(demo: true) }.disabled(busy)
                    }.font(.subheadline)
                }
            }
            if busy { HStack { ProgressView(); Text("处理中…"); Spacer(); Button("取消") { task?.cancel(); requestID = UUID(); busy = false } } }
            if let analysisMessage { Notice(text: analysisMessage) }
            if !busy && meal.photoPath == nil { Button("改用手动输入") { showPhoto = false; addManual() } }
        }
    }
    private var confirmationBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.isDemo ? "演示 · 不计入摄入" : "本餐合计").font(.caption).foregroundStyle(.secondary)
                    Text("\(meal.kcal.kcalText) kcal").font(.title2.bold()).monospacedDigit()
                }
                Spacer()
                if !initiallyConfirmed { Button("存草稿") { save(confirmed: false) }.disabled(!canSave).accessibilityLabel("保存草稿，不计入摄入") }
            }
            Button { focusedFood = nil; save(confirmed: true) } label: {
                Text(initiallyConfirmed ? "保存修改" : (meal.isDemo ? "保存演示记录" : "确认并计入摄入")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!canSave || meal.items.isEmpty)
        }.padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
    }
    private var analysisDetails: some View {
        List {
            Section { Text("这里保留每次分析的原始结果；你最终确认的数值单独保存。").font(.subheadline) }
            Section { ForEach(Array(meal.rawAnalyses.enumerated()), id: \.offset) { index, raw in
                DisclosureGroup("第 \(index + 1) 次分析 · 原始数据") { Text(raw).font(.caption.monospaced()).textSelection(.enabled) }
            } }
        }.navigationTitle("分析详情")
    }
    private func save(confirmed: Bool) {
        do { var saved = meal; saved.confirmed = confirmed; try store.saveMeal(saved); meal = saved; cleanup(); dismiss() } catch { self.error = error.localizedDescription }
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
                try Task.checkCancellation(); guard requestID == job else { return }; installPhoto(UIImage(cgImage: thumbnail))
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
                guard requestID == job else { return }
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
@MainActor private struct MealDraftItem: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private var rowLayout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8)) }
    @Binding var item: FoodItem
    var focus: FocusState<UUID?>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("食物名称", text: $item.name).font(.headline).focused(focus, equals: item.id).accessibilityLabel("食物名称")
            HStack {
                Text("\(item.consumed.kcal.kcalText) kcal").font(.title2.bold()).monospacedDigit()
                Spacer()
                Text(item.source.kind == "ai" ? "AI 估算" : item.source.kind == "database" ? "食物库" : item.source.kind == "demo" ? "演示" : "手动录入").font(.caption).foregroundStyle(.secondary)
            }
            if item.basis == "per100" {
                rowLayout {
                    Text("供餐重量")
                    TextField("克", value: $item.servedGrams, format: .number).keyboardType(.decimalPad).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing).focused(focus, equals: item.id).accessibilityLabel("供餐重量，克")
                    Text("g").foregroundStyle(.secondary)
                }
                Text("\(item.nutrients.kcal.kcalText) kcal / 100 g · \(item.preparation)").font(.caption).foregroundStyle(.secondary)
            } else {
                rowLayout {
                    Text("整份热量")
                    TextField("热量", value: $item.nutrients.kcal, format: .number).keyboardType(.decimalPad).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing).focused(focus, equals: item.id).accessibilityLabel("整份热量，kcal")
                    Text("kcal").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("实际吃下"); Spacer(); Text("\((item.eatenFraction * 100).kcalText)%").monospacedDigit() }
                Slider(value: $item.eatenFraction, in: 0...1, step: 0.01).accessibilityLabel("食用比例").accessibilityValue("\((item.eatenFraction * 100).kcalText)%")
                if let grams = item.actualGrams { Text("计入 \(grams.kcalText) g，份量已按比例计算").font(.caption).foregroundStyle(.secondary) }
            }
            if !item.questions.isEmpty { Label(item.questions.joined(separator: "；"), systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary) }
            NavigationLink { FoodItemEditor(item: $item) } label: { Text("营养、烹饪方式与来源").font(.subheadline) }
        }.padding(.vertical, 6)
        .onChange(of: item.name) { _, _ in markEdited() }
        .onChange(of: item.nutrients) { _, _ in markEdited() }
    }
    private func markEdited() {
        if item.source.kind != "manual" { item.source.kind = "manual"; item.source.label = "手动修订 · 原来源：" + item.source.label }
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
            .fuelKeyboardDismissal()
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
                .fuelKeyboardDismissal()
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
