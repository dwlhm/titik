import Foundation
import Testing
@testable import TitikCore
@testable import TitikPluginKit
@testable import TitikPlugins

@Suite("Plugin Worker Supervisor Tests")
struct WorkerSupervisorTests {

    @Test("Supervisor locates titik-worker binary")
    func test_supervisor_findWorkerBinary() {
        let binaryURL = PluginWorkerSupervisor.findWorkerBinary()
        #expect(binaryURL != nil, "titik-worker binary should be located")
    }

    @Test("Supervisor routes query streaming events correctly")
    func test_supervisor_queryStreamingEvents() async throws {
        let supervisor = PluginWorkerSupervisor()
        defer { supervisor.shutdown() }

        // Set dummy pipe writer so supervisor considers worker ready to receive queries
        let pipe = Pipe()
        supervisor.setWriterForTesting(IPCMessageWriter(handle: pipe.fileHandleForWriting))

        let (reqId, stream) = supervisor.query(pluginId: "mock.streaming", query: "hello")

        // Inject simulated worker stream events
        Task {
            supervisor.injectResponseForTesting(.streamEvent(requestId: reqId, event: .textDelta("chunk1")))
            supervisor.injectResponseForTesting(.streamEvent(requestId: reqId, event: .textDelta("chunk2")))
            supervisor.injectResponseForTesting(.streamEvent(requestId: reqId, event: .finished))
        }

        var chunks: [String] = []
        var finished = false

        for await response in stream {
            if case .streamEvent(_, let event) = response {
                switch event {
                case .textDelta(let text):
                    chunks.append(text)
                case .finished:
                    finished = true
                default:
                    break
                }
            }
        }

        #expect(chunks == ["chunk1", "chunk2"])
        #expect(finished)
    }

    @Test("Supervisor routes query error when worker returns error")
    func test_supervisor_queryErrorRouting() async throws {
        let supervisor = PluginWorkerSupervisor()
        defer { supervisor.shutdown() }

        let pipe = Pipe()
        supervisor.setWriterForTesting(IPCMessageWriter(handle: pipe.fileHandleForWriting))

        let (reqId, stream) = supervisor.query(pluginId: "non.existent", query: "test")

        Task {
            supervisor.injectResponseForTesting(.queryError(requestId: reqId, error: "Plugin 'non.existent' not found in worker"))
        }

        var receivedError = false
        for await response in stream {
            if case .queryError(let id, let err) = response {
                #expect(id == reqId)
                #expect(err.contains("not found in worker"))
                receivedError = true
            }
        }

        #expect(receivedError)
    }

    @Test("Supervisor handles query cancellation")
    func test_supervisor_queryCancellation() async throws {
        let supervisor = PluginWorkerSupervisor()
        defer { supervisor.shutdown() }

        let pipe = Pipe()
        supervisor.setWriterForTesting(IPCMessageWriter(handle: pipe.fileHandleForWriting))

        let (reqId, stream) = supervisor.query(pluginId: "some.plugin", query: "test")
        supervisor.cancelQuery(requestId: reqId)

        var count = 0
        for await _ in stream {
            count += 1
        }

        #expect(count == 0)
    }

    @Test("Supervisor recovers and fails inflight streams on simulated crash")
    func test_supervisor_crashRecovery() async throws {
        let supervisor = PluginWorkerSupervisor()
        defer { supervisor.shutdown() }

        let pipe = Pipe()
        supervisor.setWriterForTesting(IPCMessageWriter(handle: pipe.fileHandleForWriting))

        let (_, stream) = supervisor.query(pluginId: "mock.plugin", query: "hello")

        // Simulate process termination
        supervisor.handleProcessTerminationForTesting(exitCode: 9)

        var errorReceived = false
        for await response in stream {
            if case .queryError(_, let err) = response {
                #expect(err.contains("terminated"))
                errorReceived = true
            }
        }

        #expect(errorReceived)
    }
}
