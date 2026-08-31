import Foundation
import SwiftUI

public enum StreamEvent: Sendable, Equatable {
    case textDelta(String)
    case media(MediaAsset)
    case citation(CitationSource)
    case progress(fraction: Double, message: String?)
    case rateLimit(retryAfter: TimeInterval)
    case error(String)
    case finished
}

public actor StreamEmitter {
    private var continuations: [UUID: AsyncStream<StreamEvent>.Continuation] = [:]
    private var isFinished: Bool = false
    private var bufferedEvents: [StreamEvent] = []

    public init() {}

    public func stream() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let id = UUID()
            for ev in bufferedEvents {
                continuation.yield(ev)
            }
            if isFinished {
                continuation.finish()
                return
            }
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    public func emit(_ event: StreamEvent) {
        guard !isFinished else { return }
        bufferedEvents.append(event)
        for continuation in continuations.values {
            continuation.yield(event)
        }
        if case .finished = event {
            isFinished = true
            for continuation in continuations.values {
                continuation.finish()
            }
            continuations.removeAll()
        }
    }

    public func emitText(_ delta: String) {
        emit(.textDelta(delta))
    }

    public func emitMedia(_ asset: MediaAsset) {
        emit(.media(asset))
    }

    public func emitCitation(_ citation: CitationSource) {
        emit(.citation(citation))
    }

    public func emitProgress(fraction: Double, message: String? = nil) {
        emit(.progress(fraction: fraction, message: message))
    }

    public func emitRateLimit(retryAfter: TimeInterval) {
        emit(.rateLimit(retryAfter: retryAfter))
    }

    public func emitError(_ error: String) {
        emit(.error(error))
    }

    public func finish() {
        emit(.finished)
    }
}

public enum PluginCanvas: @unchecked Sendable {
    case streaming(StreamEmitter)
    case customView(AnyView)
    case list([PluginItem])
    case empty
}

public protocol TitikStreamingPlugin: TitikPlugin {
    func onQuery(_ query: String) async throws -> PluginCanvas
    func cancelActiveStream() async
}

public extension TitikStreamingPlugin {
    func cancelActiveStream() async {}
}
