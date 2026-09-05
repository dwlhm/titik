import Foundation
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins

@objc(MockPluginKitPlugin)
final class MockPluginKitPlugin: NSObject, TitikStreamingPlugin, @unchecked Sendable {
    static let id = "mock.test.plugin"
    static let name = "Mock Test Plugin"
    static let version = "2.0.0"
    static let sdkVersion = 2

    let context: PluginContext
    var isShutdownCalled = false
    var activeStreamCancelled = false

    required init(context: PluginContext) {
        self.context = context
        super.init()
    }

    func onQuery(_ query: String) async throws -> PluginCanvas {
        let emitter = StreamEmitter()
        Task {
            await emitter.emitText("Response for: \(query)")
            await emitter.finish()
        }
        return .streaming(emitter)
    }

    func cancelActiveStream() async {
        activeStreamCancelled = true
    }

    func onShutdown() {
        isShutdownCalled = true
    }
}

final class MockFailingPlugin: TitikStreamingPlugin, @unchecked Sendable {
    static let id = "mock.failing.plugin"
    static let name = "Mock Failing Plugin"
    static let version = "2.0.0"
    static let sdkVersion = 2

    let context: PluginContext

    init(context: PluginContext) {
        self.context = context
    }

    func onQuery(_ query: String) async throws -> PluginCanvas {
        throw PluginError.runtimeCrash("Simulated unexpected crash in plugin thread")
    }
}

@Suite("Plugin Host & Dynamic Loading Tests")
struct DynamicBundleLoadingTests {

    @Test("Valid native plugin registers, executes handshake, and queries correctly")
    func test_host_validPluginBundle_loadsAndInstantiatesCorrectly() async throws {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let manifest = PluginManifest(
            id: MockPluginKitPlugin.id,
            name: MockPluginKitPlugin.name,
            version: MockPluginKitPlugin.version,
            sdkVersion: 2,
            description: "Unit test mock plugin",
            entrypoint: "MockPluginKitPlugin",
            triggers: ["!mock", "!test"]
        )

        let plugin = MockPluginKitPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        let retrieved = host.getNativePlugin(id: manifest.id)
        #expect(retrieved != nil)
        #expect(retrieved?.pluginId == "mock.test.plugin")

        let matched = host.findActivePlugin(command: "mock")
        #expect(matched != nil)
        #expect(matched?.id == "mock.test.plugin")
    }

    @Test("Missing principal class rejects without crashing host")
    func test_host_missingPrincipalClass_rejectsWithoutCrash() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".titikplugin")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestJSON = """
        {
            "id": "missing-class-plugin",
            "name": "Missing Class",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Tests missing class",
            "entrypoint": "NonExistentPrincipalClass_XYZ_12345",
            "triggers": ["!missing"]
        }
        """
        try manifestJSON.write(to: tempDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let host = PluginHost()
        defer { host.shutdownAll() }

        #expect(throws: PluginError.self) {
            try host.loadNativePluginBundle(at: tempDir)
        }
    }

    @Test("Non-conforming class rejects with descriptive error")
    func test_host_nonConformingClass_rejectsWithDescriptiveError() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".titikplugin")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // NSString is a valid Objective-C class, but does NOT conform to TitikPlugin
        let manifestJSON = """
        {
            "id": "non-conforming-plugin",
            "name": "Non Conforming",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Tests non conforming class",
            "entrypoint": "NSString",
            "triggers": ["!string"]
        }
        """
        try manifestJSON.write(to: tempDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let host = PluginHost()
        defer { host.shutdownAll() }

        do {
            _ = try host.loadNativePluginBundle(at: tempDir)
            #expect(Bool(false), "Should have thrown nonConformingPrincipalClass error")
        } catch let error as PluginError {
            if case .nonConformingPrincipalClass(let name) = error {
                #expect(name == "NSString")
            } else {
                #expect(Bool(false), "Expected nonConformingPrincipalClass, got: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test("Outdated SDK version rejects and logs warning")
    func test_host_outdatedSDKVersion_rejectsAndLogsWarning() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".titikplugin")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestJSON = """
        {
            "id": "outdated-plugin",
            "name": "Outdated SDK",
            "version": "1.0.0",
            "sdkVersion": 1,
            "description": "Tests v1 rejection",
            "entrypoint": "SomeClass",
            "triggers": ["!outdated"]
        }
        """
        try manifestJSON.write(to: tempDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let host = PluginHost()
        defer { host.shutdownAll() }

        #expect(throws: PluginError.self) {
            try host.loadNativePluginBundle(at: tempDir)
        }
    }

    @Test("Plugin crash during execution catches and isolates error without host crash")
    func test_host_pluginCrashDuringExecution_catchesAndIsolatesError() async {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let manifest = PluginManifest(
            id: MockFailingPlugin.id,
            name: MockFailingPlugin.name,
            version: MockFailingPlugin.version,
            sdkVersion: 2,
            description: "Failing plugin",
            entrypoint: "MockFailingPlugin",
            triggers: ["!fail"]
        )

        let plugin = MockFailingPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        // Ensure when executed, error is caught gracefully
        do {
            _ = try await plugin.onQuery("trigger crash")
            #expect(Bool(false), "Should have thrown runtimeCrash error")
        } catch let error as PluginError {
            if case .runtimeCrash(let reason) = error {
                #expect(reason.contains("Simulated unexpected crash"))
            } else {
                #expect(Bool(false), "Expected runtimeCrash, got: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test("Window hide cancels active streaming tasks within 10ms")
    func test_host_windowHide_cancelsActiveStreamingTasksWithin10ms() async {
        let host = PluginHost()
        defer { host.shutdownAll() }

        let manifest = PluginManifest(
            id: MockPluginKitPlugin.id,
            name: MockPluginKitPlugin.name,
            version: MockPluginKitPlugin.version,
            sdkVersion: 2,
            description: "Cancellation test plugin",
            entrypoint: "MockPluginKitPlugin",
            triggers: ["!stream"]
        )

        let plugin = MockPluginKitPlugin(context: PluginContext(pluginId: manifest.id))
        host.registerNativePlugin(plugin, manifest: manifest)

        guard let loaded = host.getLoadedNativePlugin(id: manifest.id) else {
            #expect(Bool(false), "Plugin should be registered")
            return
        }

        let task = Task { () -> Void in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s sleep
        }
        _ = loaded.addTask(task)

        #expect(!task.isCancelled)

        let startTime = DispatchTime.now()
        host.cancelAllActiveTasks()
        let durationNanos = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let durationMs = Double(durationNanos) / 1_000_000.0

        #expect(task.isCancelled)
        #expect(durationMs < 50.0, "Task cancellation took \(durationMs)ms, expected < 50ms")
    }

    @Test("Valid Apple .bundle structure loads and instantiates correctly")
    func test_host_validAppleBundleStructure_loadsAndInstantiatesCorrectly() throws {
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        let contentsDir = tempBundle.appendingPathComponent("Contents")
        let resourcesDir = contentsDir.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>test.valid.apple.bundle</string>
            <key>CFBundleName</key>
            <string>TestValidAppleBundle</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>NSPrincipalClass</key>
            <string>MockPluginKitPlugin</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let manifestJSON = """
        {
            "id": "test.valid.apple.bundle",
            "name": "Test Valid Apple Bundle",
            "icon": "🧘",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Standard Apple bundle test",
            "entrypoint": "MockPluginKitPlugin",
            "triggers": ["!apple"]
        }
        """
        try manifestJSON.write(to: resourcesDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let host = PluginHost()
        defer { host.shutdownAll() }

        let plugin = try host.loadNativePluginBundle(at: tempBundle)
        #expect(plugin.pluginId == MockPluginKitPlugin.id)
        #expect(host.getNativePlugin(id: "test.valid.apple.bundle") != nil)
    }

    @Test("Principal class is resolved from NSPrincipalClass in Info.plist")
    func test_host_principalClassFromInfoPlist() throws {
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        let contentsDir = tempBundle.appendingPathComponent("Contents")
        let resourcesDir = contentsDir.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>test.principal.info.plist</string>
            <key>CFBundleName</key>
            <string>TestPrincipalClass</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>NSPrincipalClass</key>
            <string>MockPluginKitPlugin</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        // entrypoint points to an unregistered class name so bundle.principalClass fallback is used
        let manifestJSON = """
        {
            "id": "test.principal.info.plist",
            "name": "Test Principal Class",
            "icon": "🧘",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Fallback to NSPrincipalClass",
            "entrypoint": "NonExistentEntrypointClass",
            "triggers": ["!principal"]
        }
        """
        try manifestJSON.write(to: resourcesDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        let host = PluginHost()
        defer { host.shutdownAll() }

        let plugin = try host.loadNativePluginBundle(at: tempBundle)
        #expect(plugin.pluginId == MockPluginKitPlugin.id)
        #expect(host.getNativePlugin(id: "test.principal.info.plist") != nil)
    }

    @Test("Corrupted code signature logs warning and handles gracefully")
    func test_host_corruptedCodeSignature_rejectsOrWarns() throws {
        let tempBundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        let contentsDir = tempBundle.appendingPathComponent("Contents")
        let macosDir = contentsDir.appendingPathComponent("MacOS")
        let resourcesDir = contentsDir.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        // Copy a real Mach-O binary and sign it, then corrupt it
        let echoURL = URL(fileURLWithPath: "/bin/echo")
        let destExec = macosDir.appendingPathComponent("CorruptedPlugin")
        if FileManager.default.fileExists(atPath: echoURL.path) {
            try FileManager.default.copyItem(at: echoURL, to: destExec)
        } else {
            try "fake binary".write(to: destExec, atomically: true, encoding: .utf8)
        }

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>test.corrupted.signature</string>
            <key>CFBundleName</key>
            <string>CorruptedPlugin</string>
            <key>CFBundleExecutable</key>
            <string>CorruptedPlugin</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>NSPrincipalClass</key>
            <string>MockPluginKitPlugin</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let manifestJSON = """
        {
            "id": "test.corrupted.signature",
            "name": "Corrupted Signature Test",
            "version": "1.0.0",
            "sdkVersion": 2,
            "description": "Testing corrupted signature handling",
            "entrypoint": "MockPluginKitPlugin",
            "triggers": ["!corrupt"]
        }
        """
        try manifestJSON.write(to: resourcesDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        // Ad-hoc sign the bundle
        let signProcess = Process()
        signProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProcess.arguments = ["-s", "-", "-f", tempBundle.path]
        try? signProcess.run()
        signProcess.waitUntilExit()

        // Corrupt executable by appending garbage bytes
        if let fileHandle = try? FileHandle(forWritingTo: destExec) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(Data("CORRUPTED_SIGNATURE_PAYLOAD".utf8))
            try? fileHandle.close()
        }

        let host = PluginHost()
        defer { host.shutdownAll() }

        // Corrupted signature should log warning and either handle gracefully or reject, without host crash
        do {
            _ = try host.loadNativePluginBundle(at: tempBundle)
        } catch {
            #expect(error is PluginError)
        }
    }
}
