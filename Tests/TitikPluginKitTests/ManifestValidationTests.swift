import Foundation
import Testing
@testable import TitikPluginKit

@Suite("Manifest Schema Validation Tests")
struct ManifestValidationTests {

    @Test("Valid JSON loads and parses successfully")
    func test_manifest_validJSON_loadsSuccessfully() throws {
        let json = """
        {
            "id": "ask-ai",
            "name": "Ask AI",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Intelligent Assistant",
            "entrypoint": "AskAIPlugin",
            "triggers": ["ask", "ai"],
            "permissions": ["network", "keychain"],
            "preferences": {
                "defaultProvider": "opencode"
            }
        }
        """
        let manifest = try PluginManifest.validate(jsonString: json)
        #expect(manifest.id == "ask-ai")
        #expect(manifest.name == "Ask AI")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.sdkVersion == 2)
        #expect(manifest.entrypoint == "AskAIPlugin")
        #expect(manifest.triggers == ["ask", "ai"])
        #expect(manifest.normalizedBangs == ["ask", "ai"])
        #expect(manifest.permissions == ["network", "keychain"])
        #expect(manifest.preferences?["defaultProvider"] == "opencode")
    }

    @Test("Missing required fields fails validation")
    func test_manifest_missingRequiredFields_failsValidation() {
        let missingId = """
        {
            "id": "",
            "name": "Ask AI",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Assistant",
            "entrypoint": "AskAIPlugin",
            "triggers": ["!ask"]
        }
        """
        #expect(throws: PluginError.self) {
            try PluginManifest.validate(jsonString: missingId)
        }

        let missingTriggers = """
        {
            "id": "ask-ai",
            "name": "Ask AI",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Assistant",
            "entrypoint": "AskAIPlugin",
            "triggers": []
        }
        """
        #expect(throws: PluginError.self) {
            try PluginManifest.validate(jsonString: missingTriggers)
        }
    }

    @Test("Unsupported SDK version rejects with clear error")
    func test_manifest_unsupportedSDKVersion_rejectsWithClearError() {
        let oldSDK = """
        {
            "id": "legacy-plugin",
            "name": "Legacy",
            "version": "0.1.0",
            "sdkVersion": 1,
            "description": "Old plugin",
            "entrypoint": "LegacyPlugin",
            "triggers": ["!old"]
        }
        """
        do {
            _ = try PluginManifest.validate(jsonString: oldSDK)
            #expect(Bool(false), "Should have thrown incompatibleSDK error")
        } catch let error as PluginError {
            if case .incompatibleSDK(let current, let required) = error {
                #expect(current >= 2)
                #expect(required == 1)
            } else {
                #expect(Bool(false), "Expected incompatibleSDK error, got: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Corrupted JSON handled gracefully without crashing")
    func test_manifest_corruptedJSON_handledGracefullyWithoutCrash() {
        let brokenJSON = "{ invalid_json_syntax: true, "
        #expect(throws: PluginError.self) {
            try PluginManifest.validate(jsonString: brokenJSON)
        }
    }
}
