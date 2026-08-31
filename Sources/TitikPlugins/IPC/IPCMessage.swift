import Foundation
import TitikPluginKit

public enum IPCRequest: Sendable, Equatable, Codable {
    case handshake(sdkVersion: Int)
    case load(bundlePath: String, manifestData: Data)
    case unload(pluginId: String)
    case query(requestId: UUID, pluginId: String, query: String)
    case cancelQuery(requestId: UUID)
    case shutdown
}

public enum IPCResponse: Sendable, Equatable, Codable {
    case handshakeAck(workerSdkVersion: Int, success: Bool)
    case loadResult(pluginId: String, success: Bool, error: String?)
    case streamEvent(requestId: UUID, event: StreamEvent)
    case listResult(requestId: UUID, items: [PluginItem])
    case queryError(requestId: UUID, error: String)
    case heartbeat
}

public enum IPCFraming {
    public static let headerSize = 4

    /// Encodes a Codable message with a 4-byte big-endian length prefix.
    public static func encodeFrame<T: Encodable>(_ message: T) throws -> Data {
        let encoder = JSONEncoder()
        let payload = try encoder.encode(message)
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: headerSize)
        framed.append(payload)
        return framed
    }

    /// Attempts to decode the next framed message from the given buffer.
    /// If a complete frame is decoded, the frame is consumed from the buffer.
    /// Returns nil if not enough data is available.
    public static func decodeFrame<T: Decodable>(from buffer: inout Data, as type: T.Type = T.self) throws -> T? {
        guard buffer.count >= headerSize else {
            return nil
        }

        let length: UInt32 = buffer.prefix(headerSize).withUnsafeBytes { ptr in
            UInt32(bigEndian: ptr.loadUnaligned(as: UInt32.self))
        }

        let totalFrameSize = headerSize + Int(length)
        guard buffer.count >= totalFrameSize else {
            return nil
        }

        let payloadData = buffer.subdata(in: headerSize..<totalFrameSize)
        buffer.removeSubrange(0..<totalFrameSize)

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: payloadData)
    }
}
