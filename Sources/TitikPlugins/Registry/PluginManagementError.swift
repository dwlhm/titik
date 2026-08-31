import Foundation

/// Errors produced during plugin reindex operations.
public enum PluginManagementError: Error, LocalizedError, Equatable, Sendable {
    /// config.json could not be written.
    case ioError(reason: String)
    /// The PluginHost failed to load a specific bundle.
    case runtimeLoadError(id: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .ioError(let reason):
            return "Plugin config I/O error: \(reason)"
        case .runtimeLoadError(let id, let reason):
            return "Failed to load plugin '\(id)': \(reason)"
        }
    }
}
