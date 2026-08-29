import Foundation

public enum ToastType: Sendable, Equatable {
    case info
    case success
    case warning
    case error
}

public struct ToastMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let message: String
    public let icon: String?
    public let type: ToastType
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        message: String,
        icon: String? = nil,
        type: ToastType = .info,
        duration: TimeInterval = 2.5
    ) {
        self.id = id
        self.message = message
        self.icon = icon
        self.type = type
        self.duration = duration
    }
}
