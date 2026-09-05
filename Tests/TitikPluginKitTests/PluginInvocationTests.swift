import Foundation
import Testing
@testable import TitikPluginKit

@Suite("PluginInvocation Tests")
struct PluginInvocationTests {

    @Test("FlagValue string and boolean accessors")
    func testFlagValueAccessors() {
        let boolTrue = FlagValue.boolean(true)
        #expect(boolTrue.boolValue == true)
        #expect(boolTrue.stringValue == "true")

        let boolFalse = FlagValue.boolean(false)
        #expect(boolFalse.boolValue == false)
        #expect(boolFalse.stringValue == "false")

        let strVal = FlagValue.string("custom")
        #expect(strVal.stringValue == "custom")
        #expect(strVal.boolValue == false)

        let strTrueVal = FlagValue.string("yes")
        #expect(strTrueVal.boolValue == true)

        let strOneVal = FlagValue.string("1")
        #expect(strOneVal.boolValue == true)
    }

    @Test("PluginInvocation properties and helper methods")
    func testPluginInvocationHelpers() {
        let invocation = PluginInvocation(
            trigger: "zen",
            action: "new-tab",
            primaryValue: "https://apple.com",
            flags: [
                "profile": .string("work"),
                "private": .boolean(true)
            ],
            rawInput: "!zen new-tab https://apple.com --profile work --private"
        )

        #expect(invocation.trigger == "zen")
        #expect(invocation.action == "new-tab")
        #expect(invocation.primaryValue == "https://apple.com")
        #expect(invocation.rawInput == "!zen new-tab https://apple.com --profile work --private")
        #expect(invocation.flag("profile") == "work")
        #expect(invocation.flag("nonexistent") == nil)
        #expect(invocation.hasFlag("private") == true)
        #expect(invocation.hasFlag("nonexistent") == false)
    }

    @Test("Manifest cleans leading bangs on decode and init")
    func testManifestCleansLeadingBangs() {
        let manifest = PluginManifest(
            id: "test.plugin",
            name: "Test Plugin",
            version: "1.0.0",
            sdkVersion: 2,
            description: "Testing triggers",
            entrypoint: "TestPlugin",
            triggers: ["!bang", "clean"]
        )

        #expect(manifest.triggers == ["bang", "clean"])
        #expect(manifest.normalizedBangs == ["bang", "clean"])
    }
}
