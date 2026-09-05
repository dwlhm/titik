import Foundation

public struct RGBAColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = max(0.0, min(1.0, red))
        self.green = max(0.0, min(1.0, green))
        self.blue = max(0.0, min(1.0, blue))
        self.alpha = max(0.0, min(1.0, alpha))
    }

    public static func parseHex(_ hexString: String) -> RGBAColor? {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }

        let length = clean.count
        guard length == 3 || length == 4 || length == 6 || length == 8 else {
            return nil
        }

        guard let hexValue = UInt64(clean, radix: 16) else {
            return nil
        }

        let r, g, b, a: Double

        switch length {
        case 3: // RGB (4-bit per channel)
            let rVal = (hexValue >> 8) & 0xF
            let gVal = (hexValue >> 4) & 0xF
            let bVal = hexValue & 0xF
            r = Double(rVal * 17) / 255.0
            g = Double(gVal * 17) / 255.0
            b = Double(bVal * 17) / 255.0
            a = 1.0

        case 4: // RGBA (4-bit per channel)
            let rVal = (hexValue >> 12) & 0xF
            let gVal = (hexValue >> 8) & 0xF
            let bVal = (hexValue >> 4) & 0xF
            let aVal = hexValue & 0xF
            r = Double(rVal * 17) / 255.0
            g = Double(gVal * 17) / 255.0
            b = Double(bVal * 17) / 255.0
            a = Double(aVal * 17) / 255.0

        case 6: // RRGGBB (8-bit per channel)
            r = Double((hexValue >> 16) & 0xFF) / 255.0
            g = Double((hexValue >> 8) & 0xFF) / 255.0
            b = Double(hexValue & 0xFF) / 255.0
            a = 1.0

        case 8: // RRGGBBAA (8-bit per channel)
            r = Double((hexValue >> 24) & 0xFF) / 255.0
            g = Double((hexValue >> 16) & 0xFF) / 255.0
            b = Double((hexValue >> 8) & 0xFF) / 255.0
            a = Double(hexValue & 0xFF) / 255.0

        default:
            return nil
        }

        return RGBAColor(red: r, green: g, blue: b, alpha: a)
    }
}

public final class ConfigLoader: @unchecked Sendable {
    public static let shared = ConfigLoader()

    private let lock = NSLock()
    private var _currentConfig: Config
    public var currentConfig: Config {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentConfig
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _currentConfig = newValue
        }
    }
    public var configURL: URL?

    public init(config: Config = Config(), configURL: URL? = nil) {
        self._currentConfig = config
        self.configURL = configURL
    }

    public static var userConfigPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/titik/config.json")
    }

    public static var defaultBundleConfigPath: URL? {
        // Look in standard relative path for dev or bundle
        let possiblePaths = [
            Bundle.main.url(forResource: "config.default", withExtension: "json"),
            URL(fileURLWithPath: "config/config.default.json")
        ]
        for url in possiblePaths {
            if let u = url, FileManager.default.fileExists(atPath: u.path) {
                return u
            }
        }
        return nil
    }

    @discardableResult
    public func load(from url: URL? = nil) -> Config {
        let targetURL = url ?? self.configURL ?? (self === ConfigLoader.shared ? ConfigLoader.userConfigPath : nil)
        guard let targetURL else {
            return self.currentConfig
        }

        if FileManager.default.fileExists(atPath: targetURL.path) {
            do {
                let data = try Data(contentsOf: targetURL)
                let decoded = try JSONDecoder().decode(Config.self, from: data)
                self.currentConfig = decoded
                Logger.shared.info("Loaded configuration from \(targetURL.path)", subsystem: "Titik.Config")
                return decoded
            } catch {
                Logger.shared.warn("Failed to parse config at \(targetURL.path): \(error.localizedDescription). Falling back to default.", subsystem: "Titik.Config")
            }
        }

        // Try bundle/relative default config
        if let defaultURL = ConfigLoader.defaultBundleConfigPath,
           FileManager.default.fileExists(atPath: defaultURL.path) {
            do {
                let data = try Data(contentsOf: defaultURL)
                let decoded = try JSONDecoder().decode(Config.self, from: data)
                self.currentConfig = decoded
                Logger.shared.info("Loaded default fallback config from \(defaultURL.path)", subsystem: "Titik.Config")
                return decoded
            } catch {
                Logger.shared.warn("Failed to parse default config: \(error.localizedDescription)", subsystem: "Titik.Config")
            }
        }

        // Fallback to built-in struct defaults
        self.currentConfig = Config()
        return self.currentConfig
    }

    /// Persists currentConfig to ~/.config/titik/config.json atomically.
    /// - Throws: if directory creation or file write fails.
    public func save(to url: URL? = nil) throws {
        let targetURL = url ?? self.configURL ?? ConfigLoader.userConfigPath
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(currentConfig)
        try data.write(to: targetURL, options: .atomic)
        Logger.shared.info("Saved configuration to \(targetURL.path)", subsystem: "Titik.Config")
    }

    /// Ensures that ~/.config/titik/config.json exists on disk, persisting currentConfig if missing.
    /// - Returns: The file URL of the user configuration file.
    /// - Throws: If directory creation or file write fails.
    @discardableResult
    public func ensureConfigFileExists() throws -> URL {
        if !FileManager.default.fileExists(atPath: ConfigLoader.userConfigPath.path) {
            try save(to: ConfigLoader.userConfigPath)
        }
        return ConfigLoader.userConfigPath
    }
}

