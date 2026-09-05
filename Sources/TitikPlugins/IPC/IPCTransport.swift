import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import TitikCore

public final class IPCMessageWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var isClosed = false

    public init(handle: FileHandle) {
        self.handle = handle
        signal(SIGPIPE, SIG_IGN)
    }

    public func write<T: Encodable>(_ message: T) throws {
        let framed = try IPCFraming.encodeFrame(message)
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed else {
            throw POSIXError(.EPIPE)
        }

        try handle.write(contentsOf: framed)
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        try? handle.close()
    }
}

public enum IPCTransport {
    /// Starts a dedicated background reader thread reading length-prefixed frames of type T from a FileHandle.
    /// Each decoded message is immediately passed to onMessage.
    public static func startMessageReader<T: Decodable & Sendable>(
        from handle: FileHandle,
        as type: T.Type = T.self,
        onMessage: @escaping @Sendable (T) -> Void,
        onEOF: (@Sendable () -> Void)? = nil
    ) -> Thread {
        signal(SIGPIPE, SIG_IGN)
        let readerThread = Thread {
            var buffer = Data()
            let fd = handle.fileDescriptor
            var rawBuf = [UInt8](repeating: 0, count: 65536)
            while true {
                let chunk: Data
                #if canImport(Darwin)
                let bytesRead = Darwin.read(fd, &rawBuf, rawBuf.count)
                #elseif canImport(Glibc)
                let bytesRead = Glibc.read(fd, &rawBuf, rawBuf.count)
                #else
                let bytesRead = read(fd, &rawBuf, rawBuf.count)
                #endif

                if bytesRead > 0 {
                    chunk = Data(rawBuf[0..<bytesRead])
                } else {
                    // EOF or error
                    break
                }

                buffer.append(chunk)

                while true {
                    do {
                        if let message = try IPCFraming.decodeFrame(from: &buffer, as: T.self) {
                            onMessage(message)
                        } else {
                            break
                        }
                    } catch {
                        Logger.shared.error(
                            "Failed to decode IPC frame: \(error.localizedDescription)",
                            subsystem: "Titik.IPCTransport"
                        )
                        break
                    }
                }
            }

            onEOF?()
        }
        readerThread.qualityOfService = .userInteractive
        readerThread.start()
        return readerThread
    }

    /// Creates an AsyncStream yielding decoded frames of type T from a FileHandle.
    public static func makeMessageStream<T: Decodable & Sendable>(
        from handle: FileHandle,
        as type: T.Type = T.self,
        onEOF: (@Sendable () -> Void)? = nil
    ) -> AsyncStream<T> {
        let (stream, continuation) = AsyncStream.makeStream(of: T.self)
        _ = startMessageReader(
            from: handle,
            as: type,
            onMessage: { msg in
                continuation.yield(msg)
            },
            onEOF: {
                continuation.finish()
                onEOF?()
            }
        )
        return stream
    }
}
