import SwiftUI
import Combine

@MainActor
public final class ToastManager: ObservableObject {
    public static let shared = ToastManager()

    @Published public var currentToast: ToastMessage?

    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(
        message: String,
        icon: String? = nil,
        type: ToastType = .info,
        duration: TimeInterval = 2.5
    ) {
        dismissTask?.cancel()
        dismissTask = nil

        let toast = ToastMessage(
            message: message,
            icon: icon,
            type: type,
            duration: duration
        )

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.currentToast = toast
        }

        dismissTask = Task { [weak self] in
            let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            self.currentToast = nil
        }
    }
}
