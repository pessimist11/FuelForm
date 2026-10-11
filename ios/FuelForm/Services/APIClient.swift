import Foundation

struct APIClient {
    let baseURL: URL
    let token: String
    init(address: String, token: String) throws {
        guard let url = URL(string: address), let scheme = url.scheme, let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw DomainError.invalid("请填写有效的服务地址") }
        if scheme != "https" {
            #if DEBUG
            guard scheme == "http", host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") else { throw DomainError.invalid("开发 HTTP 地址仅允许 localhost 或 .local 主机；IP 地址请使用 HTTPS") }
            #else
            throw DomainError.invalid("正式构建仅支持 HTTPS 服务")
            #endif
        }
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { throw DomainError.invalid("请先在「我的」填写服务访问凭据；模型 API Key 只放后端") }
        baseURL = url; self.token = token
    }
    private struct ErrorBody: Decodable { var error: Detail?; struct Detail: Decodable { var code: String; var message: String } }
    private func send<T: Decodable>(_ path: String, body: Data?, contentType: String = "application/json") async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path)); request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 65; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type"); request.httpBody = body
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForResource = 70
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
            throw DomainError.invalid("无法连接服务，请检查地址、网络、认证及本地网络权限")
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
    struct Status: Decodable { var mode: String; var catalogVersion: String }
    func status() async throws -> Status { try await send("v1/status", body: nil) }
}
