import Foundation

/// 在售机型目录。这家店只做 MacBook，所以型号不做自由猜测——
/// 入库时点一下「常用」就能带出芯片与规格，减少手打错字。
struct MacPreset: Identifiable {
    var id: String { label }

    let modelName: String
    let chip: String
    let memory: String
    let storage: String

    /// 由型号与规格拼出来，不含需要翻译的文案，保持 String
    var label: String { "\(modelName) · \(memory)/\(storage)" }
}

enum MacCatalog {
    static let presets: [MacPreset] = [
        MacPreset(modelName: "MacBook Air M1 13\"", chip: "M1", memory: "8GB", storage: "256GB"),
        MacPreset(modelName: "MacBook Air M2 13\"", chip: "M2", memory: "8GB", storage: "256GB"),
        MacPreset(modelName: "MacBook Air M2 15\"", chip: "M2", memory: "8GB", storage: "256GB"),
        MacPreset(modelName: "MacBook Air M3 13\"", chip: "M3", memory: "8GB", storage: "256GB"),
        MacPreset(modelName: "MacBook Pro 13\" M2", chip: "M2", memory: "8GB", storage: "256GB"),
        MacPreset(modelName: "MacBook Pro 14\" M2 Pro", chip: "M2 Pro", memory: "16GB", storage: "512GB"),
        MacPreset(modelName: "MacBook Pro 14\" M3 Pro", chip: "M3 Pro", memory: "18GB", storage: "512GB"),
        MacPreset(modelName: "MacBook Pro 16\" M3 Pro", chip: "M3 Pro", memory: "18GB", storage: "512GB"),
        MacPreset(modelName: "MacBook Pro 16\" M1 Max", chip: "M1 Max", memory: "32GB", storage: "1TB"),
    ]
}
