import Foundation
import TitikCore

/// Configuration model for Notes storage location and settings.
public struct NoteConfig: Codable, Equatable, Sendable {
    public var storageDirectoryPath: String?
    public var configURL: URL?

    public enum CodingKeys: String, CodingKey {
        case storageDirectoryPath
    }

    public init(storageDirectoryPath: String? = nil, configURL: URL? = nil) {
        self.storageDirectoryPath = storageDirectoryPath
        self.configURL = configURL ?? Self.defaultConfigURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.storageDirectoryPath = try container.decodeIfPresent(String.self, forKey: .storageDirectoryPath)
        self.configURL = Self.defaultConfigURL
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storageDirectoryPath, forKey: .storageDirectoryPath)
    }

    public static var defaultConfigURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/titik/notes_config.json")
    }

    public static var defaultNotesDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/titik/notes")
    }

    public var isConfigured: Bool {
        guard let path = storageDirectoryPath else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func load(from url: URL = defaultConfigURL) -> NoteConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return NoteConfig(configURL: url)
        }
        do {
            let data = try Data(contentsOf: url)
            var config = try JSONDecoder().decode(NoteConfig.self, from: data)
            config.configURL = url
            return config
        } catch {
            return NoteConfig(configURL: url)
        }
    }

    public func save(to url: URL? = nil) throws {
        let targetURL = url ?? configURL ?? Self.defaultConfigURL
        let dir = targetURL.deletingLastPathComponent()
        do {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: targetURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save NoteConfig to \(targetURL.path): \(error.localizedDescription)", subsystem: "Titik.Notes")
            throw error
        }
    }
}
