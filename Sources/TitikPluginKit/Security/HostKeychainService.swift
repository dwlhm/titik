import Foundation
import CryptoKit

public protocol PluginKeychainService: Sendable {
    func setSecret(_ secret: String, forKey key: String) throws
    func getSecret(forKey key: String) throws -> String?
    func deleteSecret(forKey key: String) throws
}

public final class HostKeychainService: PluginKeychainService, @unchecked Sendable {
    public let pluginId: String
    public let baseURL: URL
    private let useInMemoryStore: Bool
    private let lock = NSLock()
    private var inMemoryStorage: [String: String] = [:]

    public init(pluginId: String, baseURL: URL? = nil, useInMemoryStore: Bool = false) {
        self.pluginId = pluginId
        self.baseURL = baseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("titik")
        self.useInMemoryStore = useInMemoryStore
    }

    private func namespacedKey(for key: String) -> String {
        return "titik.plugin.\(pluginId).\(key)"
    }

    private func getOrCreateSymmetricKey() throws -> SymmetricKey {
        let keyURL = baseURL.appendingPathComponent(".vault.key")

        if FileManager.default.fileExists(atPath: keyURL.path) {
            do {
                let keyData = try Data(contentsOf: keyURL)
                if keyData.count == 32 {
                    return SymmetricKey(data: keyData)
                }
            } catch {
                // If key read fails, generate a new key below
            }
        }

        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try keyData.write(to: keyURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)

        return newKey
    }

    private func loadVault() -> [String: String] {
        let vaultURL = baseURL.appendingPathComponent("secrets.vault")
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            return [:]
        }

        do {
            let encryptedData = try Data(contentsOf: vaultURL)
            let key = try getOrCreateSymmetricKey()
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let dict = try JSONDecoder().decode([String: String].self, from: decryptedData)
            return dict
        } catch {
            // Corrupted vault recovery: return empty dictionary so that vault heals gracefully on next write
            return [:]
        }
    }

    private func saveVault(_ dict: [String: String]) throws {
        let vaultURL = baseURL.appendingPathComponent("secrets.vault")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = try getOrCreateSymmetricKey()
        let plaintextData = try JSONEncoder().encode(dict)
        let sealedBox = try AES.GCM.seal(plaintextData, using: key)
        guard let encryptedData = sealedBox.combined else {
            throw PluginError.runtimeCrash("Failed to encrypt secrets vault")
        }
        try encryptedData.write(to: vaultURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vaultURL.path)
    }

    public func setSecret(_ secret: String, forKey key: String) throws {
        let scopedKey = namespacedKey(for: key)
        lock.lock()
        defer { lock.unlock() }

        if useInMemoryStore {
            inMemoryStorage[scopedKey] = secret
            return
        }

        var vault = loadVault()
        vault[scopedKey] = secret
        try saveVault(vault)
    }

    public func getSecret(forKey key: String) throws -> String? {
        let scopedKey = namespacedKey(for: key)
        lock.lock()
        defer { lock.unlock() }

        if useInMemoryStore {
            return inMemoryStorage[scopedKey]
        }

        let vault = loadVault()
        return vault[scopedKey]
    }

    public func deleteSecret(forKey key: String) throws {
        let scopedKey = namespacedKey(for: key)
        lock.lock()
        defer { lock.unlock() }

        if useInMemoryStore {
            inMemoryStorage.removeValue(forKey: scopedKey)
            return
        }

        var vault = loadVault()
        vault.removeValue(forKey: scopedKey)
        try saveVault(vault)
    }
}
