import Foundation
import SwiftData

struct AppStoreBundle {
    let container: ModelContainer
    let cloudSyncEnabled: Bool
    /// 调试库：样例数据在里面，别把它写进用户真实的备份目录
    var isDebugStore = false
}

enum AppStore {

    /// 全局共享容器：界面与 App Intent 必须用同一个，避免两个容器争用同一个文件
    static let shared: AppStoreBundle = make()

    /// 当前为本地库模式。启用 CloudKit 需同时满足两个条件（缺一不可）：
    ///   1. InfiniStock.entitlements 中解开 iCloud 三项注释
    ///   2. 构建设置 SWIFT_ACTIVE_COMPILATION_CONDITIONS 加入 CLOUD_SYNC
    /// 之所以用编译开关而非运行时探测：没有 iCloud 能力时 ModelContainer 仍可能
    /// 初始化成功（尤其在模拟器/无签名环境），会导致界面谎报"正在同步"。
    static func make() -> AppStoreBundle {
        let schema = Schema([Item.self, Order.self, Batch.self, PriceChange.self])

        #if DEBUG
        // 验收用的样例数据落在单独的库文件里。
        // 指到真实库上，一次 seed 就等于把店里现有的账删掉——这条隔离必须硬编码在这里，
        // 不能靠"记得先备份"这种口头约定。
        // 用法：在 Application Support 里放一个 use-debug-store 文件（不会被自动删除），
        // 期间所有读写都走 debug.store；删掉它即回到真实库。
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           FileManager.default.fileExists(atPath: support.appendingPathComponent("use-debug-store").path) {
            let url = support.appendingPathComponent("debug.store")
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
                fatalError(String(localized: "调试库初始化失败：\(url.path)"))
            }
            return AppStoreBundle(container: container, cloudSyncEnabled: false, isDebugStore: true)
        }
        #endif

        #if CLOUD_SYNC
        let cloudConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            return AppStoreBundle(container: container, cloudSyncEnabled: true)
        }
        #endif

        let localConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
            fatalError("本地数据库初始化失败，请检查 App 沙盒目录权限")
        }
        return AppStoreBundle(container: container, cloudSyncEnabled: false)
    }
}
