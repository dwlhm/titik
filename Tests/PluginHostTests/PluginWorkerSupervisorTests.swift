import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins

@Suite("Plugin Worker Supervisor Multi-Worker Isolation Tests")
struct PluginWorkerSupervisorTests {

    @Test("Registering two distinct plugins spawns two distinct worker instances with distinct PIDs")
    func test_multiWorker_distinctPluginsSpawnDistinctWorkersWithDistinctPIDs() async throws {
        let supervisor = PluginWorkerSupervisor()
        defer { supervisor.shutdown() }

        let workerAlpha = try await supervisor.getOrCreateWorker(for: "plugin.alpha")
        let workerBeta = try await supervisor.getOrCreateWorker(for: "plugin.beta")

        #expect(workerAlpha.isRunning)
        #expect(workerBeta.isRunning)
        #expect(workerAlpha.pluginId == "plugin.alpha")
        #expect(workerBeta.pluginId == "plugin.beta")
        #expect(workerAlpha.pid > 0)
        #expect(workerBeta.pid > 0)
        #expect(workerAlpha.pid != workerBeta.pid)
    }

    @Test("Simulating a crash on Worker Alpha recovers Worker Alpha while Worker Beta remains completely alive and responding")
    func test_multiWorker_crashIsolationAndRecovery() async throws {
        let supervisor = PluginWorkerSupervisor()
        defer { supervisor.shutdown() }

        let workerAlpha = try await supervisor.getOrCreateWorker(for: "plugin.alpha")
        let workerBeta = try await supervisor.getOrCreateWorker(for: "plugin.beta")

        let originalAlphaPid = workerAlpha.pid
        let originalBetaPid = workerBeta.pid

        #expect(originalAlphaPid != originalBetaPid)
        #expect(workerAlpha.isRunning)
        #expect(workerBeta.isRunning)

        // Kill Worker Alpha with SIGKILL
        kill(originalAlphaPid, SIGKILL)

        // Poll for Worker Alpha auto-recovery (100ms backoff + spawn)
        var recovered = false
        var newAlphaPid: Int32 = 0
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if let currentAlpha = supervisor.worker(for: "plugin.alpha"),
               currentAlpha.isRunning,
               currentAlpha.pid != originalAlphaPid {
                recovered = true
                newAlphaPid = currentAlpha.pid
                break
            }
        }

        #expect(recovered, "Worker Alpha should have auto-recovered with a new PID")
        #expect(newAlphaPid != 0)
        #expect(newAlphaPid != originalAlphaPid)

        // Worker Beta must remain completely alive and unaffected with original PID
        guard let currentBeta = supervisor.worker(for: "plugin.beta") else {
            Issue.record("Worker Beta should still exist in supervisor pool")
            return
        }

        #expect(currentBeta.isRunning, "Worker Beta should still be running")
        #expect(currentBeta.pid == originalBetaPid, "Worker Beta PID should remain identical")
    }

    @Test("Proper shutdown of all workers in pool")
    func test_multiWorker_shutdownPool() async throws {
        let supervisor = PluginWorkerSupervisor()

        let workerAlpha = try await supervisor.getOrCreateWorker(for: "plugin.alpha")
        let workerBeta = try await supervisor.getOrCreateWorker(for: "plugin.beta")

        #expect(supervisor.isWorkerRunning(for: "plugin.alpha"))
        #expect(supervisor.isWorkerRunning(for: "plugin.beta"))
        #expect(supervisor.isWorkerRunning)
        #expect(supervisor.activeWorkers.count == 2)

        supervisor.shutdown()

        #expect(!supervisor.isWorkerRunning(for: "plugin.alpha"))
        #expect(!supervisor.isWorkerRunning(for: "plugin.beta"))
        #expect(!supervisor.isWorkerRunning)
        #expect(supervisor.activeWorkers.isEmpty)

        #expect(!workerAlpha.isRunning)
        #expect(!workerBeta.isRunning)
    }
}
