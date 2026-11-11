import Foundation
import SwiftData

struct AppStoreBundle {
    let container: ModelContainer
    let cloudSyncEnabled: Bool
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
        let schema = Schema([Item.self, Order.self, Batch.self])

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
