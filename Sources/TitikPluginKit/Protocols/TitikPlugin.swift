import Foundation

public let titikSDKVersion: Int = 2

public protocol TitikPlugin: AnyObject, Sendable {
    static var sdkVersion: Int { get }
    static var id: String { get }
    static var name: String { get }
    static var version: String { get }

    init(context: PluginContext)
    var pluginId: String { get }
    func onShutdown()
}

public extension TitikPlugin {
    static var sdkVersion: Int { titikSDKVersion }
    var pluginId: String { Self.id }
    func onShutdown() {}
}

public protocol TitikGlobalSearchProvider: TitikPlugin {
    func provideGlobalSearchResults(query: String) async -> [PluginItem]
    func provideDefaultItems() async -> [PluginItem]
}

public extension TitikGlobalSearchProvider {
    func provideDefaultItems() async -> [PluginItem] { [] }
}


public enum PluginError: Error, LocalizedError, Equatable, Sendable {
    case invalidManifest(String)
    case incompatibleSDK(current: Int, required: Int)
    case missingPrincipalClass(String)
    case nonConformingPrincipalClass(String)
    case runtimeCrash(String)
    case timeout(String)
    case cancelled
    case unauthorized(String)
    case networkError(String)
    case rateLimited(retryAfter: TimeInterval?)
    case codeSignatureInvalid(String)
    case invalidBundleStructure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let reason):
            return "Invalid plugin manifest: \(reason)"
        case .incompatibleSDK(let current, let required):
            return "Incompatible SDK version: Host SDK \(current), plugin requires \(required)"
        case .missingPrincipalClass(let className):
            return "Missing principal class: \(className)"
        case .nonConformingPrincipalClass(let className):
            return "Principal class '\(className)' does not conform to TitikPlugin"
        case .runtimeCrash(let reason):
            return "Plugin runtime error: \(reason)"
        case .timeout(let reason):
            return "Timeout: \(reason)"
        case .cancelled:
            return "Operation cancelled"
        case .unauthorized(let reason):
            return "Unauthorized: \(reason)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Rate limited. Retry after \(Int(retry))s"
            }
            return "Rate limited."
        case .codeSignatureInvalid(let reason):
            return "Invalid code signature: \(reason)"
        case .invalidBundleStructure(let reason):
            return "Invalid bundle structure: \(reason)"
        }
    }
}
