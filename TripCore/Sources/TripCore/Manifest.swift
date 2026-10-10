import Foundation

public struct ModelManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var models: [ModelManifestEntry]

    public func entry(for tier: DeviceTier) -> ModelManifestEntry? { models.first { $0.tier == tier.rawValue } }

    /// 安装包内置清单（不从网络获取，技术设计 v2 §13.3）。
    public static func bundled() throws -> ModelManifest {
        guard let url = Bundle.module.url(forResource: "model-manifest", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: url))
    }
}
