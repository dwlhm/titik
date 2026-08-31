import Foundation
import Testing
@testable import TitikPluginKit
@testable import TitikPlugins

@Suite("IPC Framing & Message Serialization Tests")
struct IPCMessageTests {

    @Test("IPCRequest encode and decode roundtrip")
    func test_ipcRequest_roundtrip() throws {
        let reqId = UUID()
        let requests: [IPCRequest] = [
            .handshake(sdkVersion: 2),
            .load(bundlePath: "/path/to/test.titikplugin", manifestData: Data("{}".utf8)),
            .unload(pluginId: "test.plugin"),
            .query(requestId: reqId, pluginId: "test.plugin", query: "2+2"),
            .cancelQuery(requestId: reqId),
            .shutdown
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for req in requests {
            let data = try encoder.encode(req)
            let decoded = try decoder.decode(IPCRequest.self, from: data)
            #expect(req == decoded)
        }
    }

    @Test("IPCResponse encode and decode roundtrip")
    func test_ipcResponse_roundtrip() throws {
        let reqId = UUID()
        let responses: [IPCResponse] = [
            .handshakeAck(workerSdkVersion: 2, success: true),
            .loadResult(pluginId: "test.plugin", success: true, error: nil),
            .loadResult(pluginId: "fail.plugin", success: false, error: "Missing dylib"),
            .streamEvent(requestId: reqId, event: .textDelta("Hello")),
            .streamEvent(requestId: reqId, event: .finished),
            .listResult(requestId: reqId, items: [
                PluginItem(id: "1", title: "Item 1", subtitle: "Sub 1", category: "Test", actionPayload: "payload1", scoreBoost: 10, pluginId: "test.plugin")
            ]),
            .queryError(requestId: reqId, error: "Timeout"),
            .heartbeat
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for resp in responses {
            let data = try encoder.encode(resp)
            let decoded = try decoder.decode(IPCResponse.self, from: data)
            #expect(resp == decoded)
        }
    }

    @Test("IPCFraming encodes length prefix and decodes complete frames")
    func test_ipcFraming_encodeAndDecode() throws {
        let req = IPCRequest.handshake(sdkVersion: 2)
        var framedData = try IPCFraming.encodeFrame(req)

        #expect(framedData.count >= 4)

        // Attempt decode
        let decoded: IPCRequest? = try IPCFraming.decodeFrame(from: &framedData)
        #expect(decoded != nil)
        #expect(decoded == req)
        #expect(framedData.isEmpty)
    }

    @Test("IPCFraming handles partial chunks and multi-frame buffers")
    func test_ipcFraming_partialChunksAndMultipleFrames() throws {
        let msg1 = IPCResponse.handshakeAck(workerSdkVersion: 2, success: true)
        let msg2 = IPCResponse.heartbeat
        let msg3 = IPCResponse.loadResult(pluginId: "p1", success: true, error: nil)

        let frame1 = try IPCFraming.encodeFrame(msg1)
        let frame2 = try IPCFraming.encodeFrame(msg2)
        let frame3 = try IPCFraming.encodeFrame(msg3)

        var combined = frame1 + frame2 + frame3
        var buffer = Data()

        // Feed half of frame1
        let splitIndex = frame1.count / 2
        buffer.append(combined.prefix(splitIndex))
        combined.removeSubrange(0..<splitIndex)

        var dec1: IPCResponse? = try IPCFraming.decodeFrame(from: &buffer)
        #expect(dec1 == nil) // Incomplete frame

        // Feed remainder of combined data
        buffer.append(combined)

        dec1 = try IPCFraming.decodeFrame(from: &buffer)
        #expect(dec1 == msg1)

        let dec2: IPCResponse? = try IPCFraming.decodeFrame(from: &buffer)
        #expect(dec2 == msg2)

        let dec3: IPCResponse? = try IPCFraming.decodeFrame(from: &buffer)
        #expect(dec3 == msg3)

        #expect(buffer.isEmpty)
    }
}
