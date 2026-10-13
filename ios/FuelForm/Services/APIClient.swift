import Foundation

struct APIClient {
    let baseURL: URL
    let token: String
    init(address: String, token: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme, let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw DomainError.invalid("请填写有效的服务地址") }
        if scheme != "https" {
            #if DEBUG
            guard scheme == "http", Self.isDevelopmentHost(host) else { throw DomainError.invalid("开发 HTTP 地址仅允许 localhost、.local 主机或局域网 IPv4 地址；其他地址请使用 HTTPS") }
            #else
            throw DomainError.invalid("正式构建仅支持 HTTPS 服务")
            #endif
        }
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { throw DomainError.invalid("请先在「我的」填写服务访问凭据；模型 API Key 只放后端") }
        baseURL = url; self.token = token
    }
    private static func isDevelopmentHost(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
                && (part.count == 1 || part.first != "0")
        }) else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }
    private struct ErrorBody: Decodable { var error: Detail?; struct Detail: Decodable { var code: String; var message: String } }
    private func send<T: Decodable>(_ path: String, body: Data?, contentType: String = "application/json") async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path)); request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 65; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type"); request.httpBody = body
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForResource = 70
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, data.count <= 2 * 1024 * 1024 else { throw DomainError.invalid("服务响应无效或过大") }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
                throw DomainError.invalid(message ?? "服务返回 \(http.statusCode)，请检查配置或输入")
            }
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw DomainError.invalid("服务响应格式不符合预期") }
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            if e.code == .notConnectedToInternet { throw DomainError.invalid("当前离线，仍可手动记餐和训练；照片可先保存草稿") }
            if e.code == .timedOut { throw DomainError.invalid("请求超时，草稿未丢失，可稍后重试") }
            if e.code == .cannotFindHost || e.code == .dnsLookupFailed { throw DomainError.invalid("无法解析服务主机名。请检查地址；本地开发可改用 Mac 的局域网 IPv4 地址") }
            if e.code == .cannotConnectToHost { throw DomainError.invalid("无法连接后端主机。请确认后端正在运行、端口正确，且手机与 Mac 网络互通") }
            throw DomainError.invalid("无法连接服务（网络错误 \(e.code.rawValue)），请检查地址、网络及本地网络权限")
        }
    }
    func analyze(jpeg: Data) async throws -> AnalysisResponse {
        let boundary = "FuelForm-\(UUID().uuidString)"; var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let result: AnalysisResponse = try await send("v1/analyze", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        _ = try result.validatedItems(); return result
    }
    func plan(_ input: AIPlanRequest) async throws -> AIPlanResponse { try await send("v1/plans/draft", body: JSONEncoder().encode(input)) }
    struct Status: Decodable {
        var mode: String
        var catalogVersion: String
        var photoReady: Bool?
        var planReady: Bool?
        var photoModel: String?
        var planModel: String?
        var configurationIssues: [String]?
        var displayName: String { ["mock": "演示分析（Mock）", "openai": "OpenAI", "deepseek": "DeepSeek"][mode] ?? "未知供应商" }
        var description: String {
            if mode == "mock" { return "连接成功 · 演示分析，与图片内容无关" }
            if let issues = configurationIssues, !issues.isEmpty { return "后端已连接 · \(displayName) 尚未配置完成\n" + issues.joined(separator: "\n") }
            let models = [photoModel.map { "照片：" + $0 }, planModel.map { "训练：" + $0 }].compactMap { $0 }.joined(separator: " · ")
            return "后端已连接 · \(displayName)\n\(models)\n实际模型调用仍需通过分析或生成草稿验证"
        }
    }
    func status() async throws -> Status { try await send("v1/status", body: nil) }
}
