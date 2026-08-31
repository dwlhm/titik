import Foundation
import TitikPluginKit

public enum ChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let role: ChatRole
    public let content: String
    public let timestamp: Date
    public let mediaAssets: [MediaAsset]
    public let citations: [CitationSource]

    public init(
        id: String = UUID().uuidString,
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        mediaAssets: [MediaAsset] = [],
        citations: [CitationSource] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.mediaAssets = mediaAssets
        self.citations = citations
    }

    public var estimatedTokens: Int {
        // Standard rule of thumb: ~4 characters per token
        let charCount = content.count
        return max(1, Int(ceil(Double(charCount) / 4.0)))
    }
}

public actor AISessionCoordinator {
    public private(set) var messages: [ChatMessage] = []
    public let maxTokens: Int
    public let maxTurns: Int
    public var systemPrompt: String?

    public init(maxTokens: Int = 8192, maxTurns: Int = 10, systemPrompt: String? = nil) {
        self.maxTokens = maxTokens
        self.maxTurns = maxTurns
        self.systemPrompt = systemPrompt

        if let sys = systemPrompt, !sys.isEmpty {
            messages.append(ChatMessage(role: .system, content: sys))
        }
    }

    public var turnCount: Int {
        messages.filter { $0.role != .system }.count
    }

    public var totalEstimatedTokens: Int {
        messages.reduce(0) { $0 + $1.estimatedTokens }
    }

    public func addMessage(_ message: ChatMessage) {
        messages.append(message)
        pruneHistoryIfNeeded()
    }

    @discardableResult
    public func appendTurn(
        role: ChatRole,
        content: String,
        mediaAssets: [MediaAsset] = [],
        citations: [CitationSource] = []
    ) -> ChatMessage {
        let msg = ChatMessage(
            role: role,
            content: content,
            timestamp: Date(),
            mediaAssets: mediaAssets,
            citations: citations
        )
        addMessage(msg)
        return msg
    }

    public func pruneHistoryIfNeeded() {
        // 1. Turn-based pruning (FIFO, preserving system message)
        let hasSystem = messages.first?.role == .system
        let systemOffset = hasSystem ? 1 : 0

        while (messages.count - systemOffset) > maxTurns {
            // Remove the oldest non-system message
            if messages.count > systemOffset {
                messages.remove(at: systemOffset)
            } else {
                break
            }
        }

        // 2. Token-budget-based pruning (FIFO, preserving system message)
        while totalEstimatedTokens > maxTokens && (messages.count - systemOffset) > 1 {
            if messages.count > systemOffset {
                messages.remove(at: systemOffset)
            } else {
                break
            }
        }
    }

    public func reset() {
        messages.removeAll()
        if let sys = systemPrompt, !sys.isEmpty {
            messages.append(ChatMessage(role: .system, content: sys))
        }
    }

    public func setSystemPrompt(_ newPrompt: String?) {
        self.systemPrompt = newPrompt
        if messages.first?.role == .system {
            messages.removeFirst()
        }
        if let newPrompt = newPrompt, !newPrompt.isEmpty {
            messages.insert(ChatMessage(role: .system, content: newPrompt), at: 0)
        }
        pruneHistoryIfNeeded()
    }

    public func history() -> [ChatMessage] {
        return messages
    }
}
