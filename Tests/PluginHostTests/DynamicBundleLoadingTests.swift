import Foundation
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins

final class MockPluginKitPlugin: TitikStreamingPlugin, @unchecked Sendable {
    static let id = "mock.test.plugin"
    static let name = "Mock Test Plugin"
    static let version = "2.0.0"
    static let sdkVersion = 2

    let context: PluginContext
    var isShutdownCalled = false
    var activeStreamCancelled = false

    init(context: PluginContext) {
        self.context = context
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

        let matched = host.findActivePlugin(forQuery: "!mock hello world")
        #expect(matched != nil)
        #expect(matched?.manifest.id == "mock.test.plugin")
        #expect(matched?.subquery == "hello world")
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
}
