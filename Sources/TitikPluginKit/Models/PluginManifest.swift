import Foundation

public struct PluginManifest: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let icon: String?
    public let version: String
    public let sdkVersion: Int
    public let description: String
    public let entrypoint: String
    public let triggers: [String]
    public let permissions: [String]
    public let preferences: [String: String]?

    public var normalizedBangs: [String] {
        triggers.map { trigger in
            trigger.hasPrefix("!") ? String(trigger.dropFirst()) : trigger
        }
    }

    public init(
        id: String,
        name: String,
        icon: String? = nil,
        version: String,
        sdkVersion: Int = 2,
        description: String,
        entrypoint: String,
        triggers: [String],
        permissions: [String] = [],
        preferences: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.version = version
        self.sdkVersion = sdkVersion
        self.description = description
        self.entrypoint = entrypoint
        self.triggers = triggers.map { $0.hasPrefix("!") ? String($0.dropFirst()) : $0 }
        self.permissions = permissions
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, version, sdkVersion, description, entrypoint, triggers, permissions, preferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        self.version = try container.decode(String.self, forKey: .version)
        self.sdkVersion = try container.decodeIfPresent(Int.self, forKey: .sdkVersion) ?? 2
        self.description = try container.decode(String.self, forKey: .description)
        self.entrypoint = try container.decode(String.self, forKey: .entrypoint)
        let rawTriggers = try container.decode([String].self, forKey: .triggers)
        self.triggers = rawTriggers.map { $0.hasPrefix("!") ? String($0.dropFirst()) : $0 }
        self.permissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        self.preferences = try container.decodeIfPresent([String: String].self, forKey: .preferences)
    }

    public static func validate(jsonData: Data) throws -> PluginManifest {
        let decoder = JSONDecoder()
        let manifest: PluginManifest
        do {
            manifest = try decoder.decode(PluginManifest.self, from: jsonData)
        } catch {
            throw PluginError.invalidManifest(error.localizedDescription)
        }

        if manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PluginError.invalidManifest("Field 'id' cannot be empty")
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PluginError.invalidManifest("Field 'name' cannot be empty")
        }
        if manifest.entrypoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PluginError.invalidManifest("Field 'entrypoint' cannot be empty")
        }
        if manifest.triggers.isEmpty {
            throw PluginError.invalidManifest("Field 'triggers' must contain at least one trigger")
        }
        if manifest.sdkVersion < 2 {
            throw PluginError.incompatibleSDK(current: titikSDKVersion, required: manifest.sdkVersion)
        }

        return manifest
    }

    public static func validate(jsonString: String) throws -> PluginManifest {
        guard let data = jsonString.data(using: .utf8) else {
            throw PluginError.invalidManifest("Unable to parse string into UTF8 data")
        }
        return try validate(jsonData: data)
    }
}
