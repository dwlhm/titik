import Foundation
import Testing
@testable import TitikPluginKit

@Suite("Keychain Security & Isolation Tests")
struct KeychainSecurityTests {

    private func makeTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("titik_vault_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @Test("AES-256-GCM encrypted persistence at rest and round-trip verification")
    func test_keychain_aesGcm_encryptedPersistence() throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretValue = "super_secret_token_12345"
        let keychain1 = HostKeychainService(pluginId: "test.plugin.a", baseURL: tempDir)
        try keychain1.setSecret(secretValue, forKey: "auth_token")

        let fetched = try keychain1.getSecret(forKey: "auth_token")
        #expect(fetched == secretValue)

        // Verify files exist on disk
        let vaultURL = tempDir.appendingPathComponent("secrets.vault")
        let keyURL = tempDir.appendingPathComponent(".vault.key")
        #expect(FileManager.default.fileExists(atPath: vaultURL.path))
        #expect(FileManager.default.fileExists(atPath: keyURL.path))

        // Verify key size is 256 bits (32 bytes)
        let keyData = try Data(contentsOf: keyURL)
        #expect(keyData.count == 32)

        // Verify file permissions (0600)
        let vaultAttrs = try FileManager.default.attributesOfItem(atPath: vaultURL.path)
        let keyAttrs = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        let vaultPerms = (vaultAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let keyPerms = (keyAttrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(vaultPerms == 0o600)
        #expect(keyPerms == 0o600)

        // Verify ciphertext does not contain plaintext
        let rawVaultData = try Data(contentsOf: vaultURL)
        let rawVaultString = String(decoding: rawVaultData, as: UTF8.self)
        #expect(!rawVaultString.contains(secretValue))

        // Verify persistence across fresh service instances
        let keychain2 = HostKeychainService(pluginId: "test.plugin.a", baseURL: tempDir)
        let fetchedFromNewInstance = try keychain2.getSecret(forKey: "auth_token")
        #expect(fetchedFromNewInstance == secretValue)
    }

    @Test("Scoped namespace isolation prevents cross-plugin secret access")
    func test_keychain_scopedNamespaceIsolation_crossPluginAccessBlocked() throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pluginA = HostKeychainService(pluginId: "plugin.alpha", baseURL: tempDir)
        let pluginB = HostKeychainService(pluginId: "plugin.beta", baseURL: tempDir)

        try pluginA.setSecret("alpha_api_key_xyz", forKey: "api_key")
        try pluginB.setSecret("beta_api_key_abc", forKey: "api_key")

        let alphaKey = try pluginA.getSecret(forKey: "api_key")
        let betaKey = try pluginB.getSecret(forKey: "api_key")

        #expect(alphaKey == "alpha_api_key_xyz")
        #expect(betaKey == "beta_api_key_abc")
        #expect(alphaKey != betaKey)
    }

    @Test("Keychain delete secret removes entry completely from vault")
    func test_keychain_deleteSecret_removesEntryCompletely() throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keychain = HostKeychainService(pluginId: "test.plugin.delete", baseURL: tempDir)
        try keychain.setSecret("temp_value", forKey: "temp_key")
        #expect(try keychain.getSecret(forKey: "temp_key") == "temp_value")

        try keychain.deleteSecret(forKey: "temp_key")
        let deletedValue = try keychain.getSecret(forKey: "temp_key")
        #expect(deletedValue == nil)

        // Verify deletion persists across new instance
        let keychain2 = HostKeychainService(pluginId: "test.plugin.delete", baseURL: tempDir)
        #expect(try keychain2.getSecret(forKey: "temp_key") == nil)
    }

    @Test("Corrupted vault recovery handles malformed ciphertext gracefully")
    func test_keychain_corruptedVaultRecovery() throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vaultURL = tempDir.appendingPathComponent("secrets.vault")
        let corruptData = Data("MALFORMED_NON_GCM_ENCRYPTED_DATA_BYTES".utf8)
        try corruptData.write(to: vaultURL)

        let keychain = HostKeychainService(pluginId: "test.plugin.corrupt", baseURL: tempDir)
        // Reading corrupted vault should return nil without throwing runtime crash
        let fetched = try keychain.getSecret(forKey: "nonexistent")
        #expect(fetched == nil)

        // Writing to corrupted vault should heal and write valid encrypted vault
        try keychain.setSecret("healed_secret_value", forKey: "healed_key")
        let recovered = try keychain.getSecret(forKey: "healed_key")
        #expect(recovered == "healed_secret_value")

        // Fresh instance can read healed vault
        let keychain2 = HostKeychainService(pluginId: "test.plugin.corrupt", baseURL: tempDir)
        #expect(try keychain2.getSecret(forKey: "healed_key") == "healed_secret_value")
    }

    @Test("Corrupted key file recovery generates fresh key")
    func test_keychain_corruptedKeyRecovery() throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyURL = tempDir.appendingPathComponent(".vault.key")
        let invalidKeyData = Data([0x01, 0x02, 0x03]) // Invalid key size (3 bytes instead of 32)
        try invalidKeyData.write(to: keyURL)

        let keychain = HostKeychainService(pluginId: "test.plugin.corruptkey", baseURL: tempDir)
        try keychain.setSecret("recovered_with_new_key", forKey: "test_key")

        let fetched = try keychain.getSecret(forKey: "test_key")
        #expect(fetched == "recovered_with_new_key")

        let newKeyData = try Data(contentsOf: keyURL)
        #expect(newKeyData.count == 32)
    }

    @Test("In-memory store mode operates without writing vault to disk")
    func test_keychain_inMemoryStore_doesNotTouchDisk() throws {
        let tempDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keychain = HostKeychainService(pluginId: "test.plugin.mem", baseURL: tempDir, useInMemoryStore: true)
        try keychain.setSecret("mem_only_token", forKey: "token")

        let fetched = try keychain.getSecret(forKey: "token")
        #expect(fetched == "mem_only_token")

        let vaultURL = tempDir.appendingPathComponent("secrets.vault")
        #expect(!FileManager.default.fileExists(atPath: vaultURL.path))
    }
}
