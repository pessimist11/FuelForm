import SwiftUI
import SwiftData

@main @MainActor struct FuelFormApp: App {
    private let container: ModelContainer?
    private let store: AppStore?
    private let failure: String?
    init() {
        do {
            let schema = Schema(versionedSchema: FuelSchemaV1.self)
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            let c = try ModelContainer(for: schema, migrationPlan: FuelMigrations.self, configurations: [config])
            container = c; store = try AppStore(container: c); failure = nil
        } catch { container = nil; store = nil; failure = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let store {
                RootView().environment(store)
            } else {
                ContentUnavailableView("无法打开本地记录", systemImage: "externaldrive.badge.exclamationmark", description: Text("\(failure ?? "未知错误")\n原数据未清空。请保留 App，排查版本或存储问题。"))
            }
        }
    }
}
