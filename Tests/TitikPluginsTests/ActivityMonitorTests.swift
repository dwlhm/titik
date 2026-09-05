import Foundation
import AppKit
import Testing
@testable import TitikCore
@testable import TitikKeymap
@testable import TitikPluginKit
@testable import TitikPlugins
@testable import TitikUI

@Suite("ActivityMonitor Unit & Integration Tests")
struct ActivityMonitorTests {

    private func makeKeyEvent(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    // MARK: - 1. Sampler Metrics

    @Test("DarwinProcessSampler enumerates active processes and vitals on macOS")
    func testDarwinProcessSamplerMetrics() {
        let sampler = DarwinProcessSampler()
        let (processes, vitals) = sampler.sample()

        #expect(!processes.isEmpty)
        #expect(vitals.processCount == processes.count)
        #expect(vitals.totalMemoryBytes > 0)
        #expect(vitals.usedMemoryBytes > 0)
        #expect(vitals.overallCpuPercent >= 0.0 && vitals.overallCpuPercent <= 100.0)

        // Verify presence of current process
        let currentPid = getpid()
        let selfEntry = processes.first(where: { $0.pid == currentPid })
        #expect(selfEntry != nil)
        if let selfEntry = selfEntry {
            #expect(!selfEntry.name.isEmpty)
            #expect(selfEntry.memoryBytes > 0)
            #expect(!selfEntry.user.isEmpty)
        }
    }

    @Test("DarwinProcessSampler resolves process names and active PIDs list")
    func testDarwinProcessSamplerPids() {
        let sampler = DarwinProcessSampler()
        let pids = sampler.enumerateActivePids()
        #expect(!pids.isEmpty)
        #expect(pids.contains(getpid()))

        let currentName = DarwinProcessSampler.processName(for: getpid())
        #expect(!currentName.isEmpty)
    }

    // MARK: - 2. Signal Safety & Error Mapping

    @Test("Signal safety: non-existent PID produces processNotFound error")
    func testSignalSafetyNonExistentPid() {
        let sampler = DarwinProcessSampler()
        let nonExistentPid: pid_t = 999_999

        let termResult = sampler.killProcess(pid: nonExistentPid, signal: SIGTERM)
        switch termResult {
        case .failure(let error):
            #expect(error == .processNotFound(pid: nonExistentPid))
            #expect(error.localizedDescription.contains("999999"))
        case .success:
            #expect(Bool(false), "Sending signal to non-existent PID 999999 should fail with ESRCH")
        }

        let killResult = sampler.killProcess(pid: nonExistentPid, signal: SIGKILL)
        switch killResult {
        case .failure(let error):
            #expect(error == .processNotFound(pid: nonExistentPid))
        case .success:
            #expect(Bool(false), "Sending SIGKILL to non-existent PID 999999 should fail with ESRCH")
        }
    }

    // MARK: - 3. Filtering & Search

    @MainActor
    @Test("ViewModel filters processes by name and PID case-insensitively")
    func testViewModelFiltering() {
        let viewModel = ActivityMonitorViewModel()
        defer { viewModel.stop() }

        let sampleProcesses = [
            ProcessEntry(pid: 101, name: "WindowServer", cpuPercent: 5.2, memoryBytes: 500_000_000, user: "_windowserver", isSystemProcess: true),
            ProcessEntry(pid: 202, name: "Finder", cpuPercent: 1.1, memoryBytes: 250_000_000, user: "testuser", isSystemProcess: false),
            ProcessEntry(pid: 303, name: "Terminal", cpuPercent: 0.5, memoryBytes: 150_000_000, user: "testuser", isSystemProcess: false),
            ProcessEntry(pid: 404, name: "titik", cpuPercent: 2.3, memoryBytes: 80_000_000, user: "testuser", isSystemProcess: false)
        ]

        viewModel.updateProcesses(newProcesses: sampleProcesses)

        // Substring match on name
        viewModel.searchQuery = "term"
        #expect(viewModel.filteredProcesses.count == 1)
        #expect(viewModel.filteredProcesses.first?.pid == 303)

        // Substring match on PID
        viewModel.searchQuery = "404"
        #expect(viewModel.filteredProcesses.count == 1)
        #expect(viewModel.filteredProcesses.first?.name == "titik")

        // Substring match on username
        viewModel.searchQuery = "windowserver"
        #expect(viewModel.filteredProcesses.count == 1)
        #expect(viewModel.filteredProcesses.first?.pid == 101)

        // Empty query restores full list
        viewModel.searchQuery = ""
        #expect(viewModel.filteredProcesses.count == 4)
    }

    // MARK: - 4. Sorting & Cycling

    @MainActor
    @Test("ViewModel sort column cycling transitions between CPU, Memory, PID, and Name")
    func testViewModelSortCycling() {
        let viewModel = ActivityMonitorViewModel()
        defer { viewModel.stop() }

        #expect(viewModel.sortColumn == .cpu)

        viewModel.toggleSort()
        #expect(viewModel.sortColumn == .memory)

        viewModel.toggleSort()
        #expect(viewModel.sortColumn == .pid)

        viewModel.toggleSort()
        #expect(viewModel.sortColumn == .name)

        viewModel.toggleSort()
        #expect(viewModel.sortColumn == .cpu)
    }

    // MARK: - 5. Confirmation State Transitions

    @MainActor
    @Test("Confirmation flow: Cmd+Delete and Cmd+Shift+Delete set pending actions; Esc clears")
    func testConfirmationFlow() {
        let viewModel = ActivityMonitorViewModel()
        defer { viewModel.stop() }

        let sampleProcesses = [
            ProcessEntry(pid: 501, name: "HeavyApp", cpuPercent: 99.0, memoryBytes: 1_000_000_000, user: "user", isSystemProcess: false)
        ]
        viewModel.updateProcesses(newProcesses: sampleProcesses)
        viewModel.selectedIndex = 0

        #expect(viewModel.pendingConfirmation == nil)

        // 1. Trigger Cmd + Delete -> Graceful Terminate
        let cmdDelete = makeKeyEvent(keyCode: Keycode.delete.rawValue, modifierFlags: [.command])
        let handledTerm = viewModel.keymapScope.trigger(event: cmdDelete)
        #expect(handledTerm == true)
        #expect(viewModel.pendingConfirmation != nil)
        #expect(viewModel.pendingConfirmation?.action == .graceful)
        #expect(viewModel.pendingConfirmation?.target.pid == 501)

        // 2. Press Esc -> Clears confirmation without signaling
        let escEvent = makeKeyEvent(keyCode: Keycode.escape.rawValue)
        let handledEsc = viewModel.keymapScope.trigger(event: escEvent)
        #expect(handledEsc == true)
        #expect(viewModel.pendingConfirmation == nil)

        // 3. Trigger Cmd + Shift + Delete -> Force Kill
        let cmdShiftDelete = makeKeyEvent(keyCode: Keycode.delete.rawValue, modifierFlags: [.command, .shift])
        let handledKill = viewModel.keymapScope.trigger(event: cmdShiftDelete)
        #expect(handledKill == true)
        #expect(viewModel.pendingConfirmation != nil)
        #expect(viewModel.pendingConfirmation?.action == .force)
        #expect(viewModel.pendingConfirmation?.target.pid == 501)

        // 4. Press 'N' -> Cancels confirmation
        let nEvent = makeKeyEvent(keyCode: Keycode.n.rawValue)
        let handledN = viewModel.keymapScope.trigger(event: nEvent)
        #expect(handledN == true)
        #expect(viewModel.pendingConfirmation == nil)
    }

    @MainActor
    @Test("Confirmation flow: 'Y' or Return triggers execution and clears confirmation")
    func testConfirmationExecution() {
        let viewModel = ActivityMonitorViewModel()
        defer { viewModel.stop() }

        let sampleProcesses = [
            ProcessEntry(pid: 999_998, name: "DeadApp", cpuPercent: 0.0, memoryBytes: 10_000, user: "user", isSystemProcess: false)
        ]
        viewModel.updateProcesses(newProcesses: sampleProcesses)
        viewModel.selectedIndex = 0

        // Set pending graceful terminate
        viewModel.requestGracefulTerminate()
        #expect(viewModel.pendingConfirmation != nil)

        // Press 'Y' to confirm
        let yEvent = makeKeyEvent(keyCode: Keycode.y.rawValue)
        let handledY = viewModel.keymapScope.trigger(event: yEvent)
        #expect(handledY == true)

        // Confirmation must be dismissed
        #expect(viewModel.pendingConfirmation == nil)
        // Error toast set for non-existent process
        #expect(viewModel.statusMessage != nil)
    }

    // MARK: - 6. Manifest & PluginKit Integration

    @Test("Manifest metadata matches specification")
    func testManifestMetadata() {
        #expect(activityMonitorPluginManifest.id == "titik.plugin.activitymonitor")
        #expect(activityMonitorPluginManifest.name == "Activity Monitor")
        #expect(activityMonitorPluginManifest.triggers.contains("activity"))
        #expect(activityMonitorPluginManifest.triggers.contains("top"))
        #expect(activityMonitorPluginManifest.triggers.contains("ps"))
        #expect(activityMonitorPluginManifest.normalizedBangs.contains("activity"))
        #expect(activityMonitorPluginManifest.normalizedBangs.contains("top"))
        #expect(activityMonitorPluginManifest.normalizedBangs.contains("ps"))
        #expect(activityMonitorPluginManifest.permissions.contains("process:signal"))
        #expect(activityMonitorPluginManifest.permissions.contains("system:metrics"))
        #expect(activityMonitorPluginManifest.entrypoint == "ActivityMonitorPlugin")
    }

    @MainActor
    @Test("Plugin conforms to PluginUIRepresentable and delegates query and navigation")
    func testPluginUIRepresentable() {
        let plugin = ActivityMonitorPlugin(context: PluginContext(pluginId: ActivityMonitorPlugin.id))
        defer { plugin.onShutdown() }

        #expect(plugin.commands.isEmpty)

        plugin.handleSearchQuery("WindowServer")
        #expect(plugin.viewModel.searchQuery == "WindowServer")

        #expect(plugin.customView != nil)
    }

    @Test("PluginHost loads ActivityMonitor dynamic bundle")
    func testDynamicBundleLoading() throws {
        let bundlePath = "bin/plugins/ActivityMonitor.bundle"
        guard FileManager.default.fileExists(atPath: bundlePath) else { return }

        let host = PluginHost()
        defer { host.shutdownAll() }

        let bundleURL = URL(fileURLWithPath: bundlePath)
        let loadedPlugin = try host.loadNativePluginBundle(at: bundleURL)

        #expect(loadedPlugin.pluginId == "titik.plugin.activitymonitor")
    }
}
