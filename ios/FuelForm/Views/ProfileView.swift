import SwiftUI
import Charts

@MainActor struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("serviceURL") private var serviceURL = "http://localhost:8000"
    @FocusState private var inputFocused: Bool
    @State private var profile = Profile()
    @State private var token = ""
    @State private var applyToday = true
    @State private var weight: Double?
    @State private var weightDate = Date()
    @State private var exportURL: URL?
    @State private var error: String?
    @State private var message: String?
    @State private var credentialMessage: String?
    @State private var serviceStatus: APIClient.Status?
    @State private var serviceBusy = false
    @State private var statusTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section("个人资料（可留空）") {
                OptionalNumber(title: "身高 cm", value: $profile.heightCM, focus: $inputFocused)
                OptionalNumber(title: "当前体重 kg", value: $profile.weightKG, focus: $inputFocused)
                HStack { Text("年龄"); TextField("未填写", value: $profile.age, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).focused($inputFocused) }
                Picker("生理性别", selection: $profile.sex) { ForEach(["未填写", "女性", "男性", "其他 / 不便填写"], id: \.self) { Text($0) } }
                Picker("活动水平", selection: $profile.activity) { ForEach(["未填写", "久坐", "轻度活动", "中度活动", "高度活动"], id: \.self) { Text($0) } }
            }
            Section("热量目标与消耗估算") {
                OptionalNumber(title: "摄入目标 kcal", value: $profile.intakeTarget, focus: $inputFocused)
                OptionalNumber(title: "每日估算总消耗 kcal", value: $profile.expenditure, focus: $inputFocused)
                Notice(text: "第一版采用你手动设置的总消耗，未填写时不生成个性化缺口。此值应已包含日常活动，App 不另加计划训练消耗。")
                Toggle("同时明确更新今日快照", isOn: $applyToday)
                Button("保存资料与设置") { saveProfile() }
            }
            Section("体重记录") {
                DatePicker("称重日期", selection: $weightDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                OptionalNumber(title: "体重 kg", value: $weight, focus: $inputFocused)
                Button("添加体重记录") {
                    guard let weight, weight.isFinite, (1...500).contains(weight) else { error = "请填写有效体重（1–500 kg）"; return }
                    do { try store.change { $0.weights.append(WeightEntry(date: weightDate, kg: weight)) }; self.weight = nil; message = "体重记录已保存" } catch { self.error = error.localizedDescription }
                }
                if !store.state.weights.isEmpty {
                    Chart(store.state.weights.sorted { $0.date < $1.date }) { w in PointMark(x: .value("日期", w.date), y: .value("体重 kg", w.kg)).foregroundStyle(.teal) }.frame(height: 150).accessibilityLabel("体重记录散点图，千克")
                    ForEach(store.state.weights.sorted { $0.date > $1.date }) { w in HStack { Text(w.date.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text("\(w.kg.formatted()) kg") } }.onDelete { offsets in
                        let sorted = store.state.weights.sorted { $0.date > $1.date }; let ids = Set(offsets.map { sorted[$0].id })
                        do { try store.change { $0.weights.removeAll { ids.contains($0.id) } } } catch { self.error = error.localizedDescription }
                    }
                }
                Notice(text: "短期体重变化不直接代表脂肪变化。这里不预测减重日期。")
            }
            Section("近期已记录摄入") {
                let keys = (-13...0).map { DayKey.adding($0, to: DayKey.make(Date())) }
                Chart {
                    ForEach(keys, id: \.self) { key in
                        let summary = store.state.summary(key)
                        if summary.hasRecords || store.state.days.first(where: { $0.dayKey == key })?.complete == true {
                            BarMark(x: .value("日期", String(key.suffix(5))), y: .value("已记录 kcal", summary.intake)).foregroundStyle(.teal)
                        }
                    }
                }.frame(height: 160).accessibilityLabel("最近十四天已记录摄入，未记录日期不绘制柱")
                Notice(text: "空缺日期表示摄入未知；柱高只代表已确认记录，并不自动代表全天记全。")
            }
            Section("分析服务") {
                TextField("服务地址", text: $serviceURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).focused($inputFocused)
                SecureField("服务访问凭据（非模型 API Key）", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().focused($inputFocused)
                    .onChange(of: token) { _, _ in credentialMessage = nil }
                Button("将凭据保存到 Keychain") { saveServiceCredential() }
                if let credentialMessage { Notice(text: credentialMessage, symbol: "checkmark.circle") }
                Button(serviceBusy ? "检查中…" : "检查后端连接与模式") { checkService() }.disabled(serviceBusy)
                if let serviceStatus { Notice(text: serviceStatus.description, symbol: serviceStatus.configurationIssues?.isEmpty == false ? "exclamationmark.circle" : "network") }
                Notice(text: "模型 API Key 只填写到后端 .env。模拟器 localhost 指向 Mac；真机指向手机自身。开发时填写同一网络下 Mac 的 .local 主机名或局域网 IPv4 地址；主机名连不上时可尝试 IP。正式构建使用 HTTPS。")
            }
            Section("记录导出") {
                Notice(text: "导出格式版本 1，包含资料、体重、目标、餐次、草稿和训练日志。包含照片相对路径，但不包含照片文件；不是完整备份，暂不支持恢复。")
                Button("生成 JSON 导出") { do { exportURL = try store.export(); message = "导出已生成，可分享或存到文件" } catch { self.error = error.localizedDescription } }
                if let exportURL { ShareLink(item: exportURL) { Label("分享 / 保存 JSON", systemImage: "square.and.arrow.up") } }
            }
            if let message { Section { Notice(text: message, symbol: "checkmark.circle") } }
            Section { Text("FuelForm 1.0 · 个人本地记录\n没有自动注入的演示餐次。演示餐次单独分区，不计入个人统计；手动核对并转为个人草稿后才能计入。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("我的")
            .fuelKeyboardDismissal()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("保存") { saveProfile() }.accessibilityLabel("保存资料与目标") }
            }
            .onAppear { profile = store.state.profile; do { token = try ServiceKeychain.read() } catch { self.error = error.localizedDescription } }
            .onDisappear { statusTask?.cancel() }
            .fuelError($error)
    }
    private func saveProfile() {
        inputFocused = false
        do { try store.saveProfile(profile, applyToday: applyToday); message = "资料已保存；过去日期的目标快照未修改" }
        catch { self.error = error.localizedDescription }
    }
    private func saveServiceCredential() {
        inputFocused = false
        credentialMessage = nil
        do {
            try ServiceKeychain.save(token)
            credentialMessage = token.isEmpty ? "已清除保存在 Keychain 中的服务凭据" : "服务访问凭据已保存到 Keychain"
        } catch { self.error = error.localizedDescription }
    }
    private func checkService() {
        inputFocused = false; serviceStatus = nil; serviceBusy = true
        statusTask = Task { @MainActor in
            defer { serviceBusy = false }
            do { let status = try await APIClient(address: serviceURL, token: token).status(); try Task.checkCancellation(); serviceStatus = status }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
