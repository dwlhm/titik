import Foundation

public final class Logger: @unchecked Sendable {
    public enum Level: Int, Comparable, Sendable {
        case trace = 0
        case debug = 1
        case info = 2
        case warn = 3
        case error = 4

        public var name: String {
            switch self {
            case .trace: return "TRACE"
            case .debug: return "DEBUG"
            case .info:  return "INFO"
            case .warn:  return "WARN"
            case .error: return "ERROR"
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public static let shared = Logger()

    private let lock = NSLock()
    public var minimumLevel: Level = .info
    public var logHandler: ((String) -> Void)?

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    public init(minimumLevel: Level = .info) {
        self.minimumLevel = minimumLevel
    }

    public func log(_ level: Level, subsystem: String = "Titik", message: String) {
        guard level >= minimumLevel else { return }

        lock.lock()
        defer { lock.unlock() }

        let timestamp = dateFormatter.string(from: Date())
        let formatted = "[\(timestamp)] [\(level.name)] [\(subsystem)] \(message)"

        if let handler = logHandler {
            handler(formatted)
        } else {
            print(formatted)
        }
    }

    public func trace(_ message: String, subsystem: String = "Titik") {
        log(.trace, subsystem: subsystem, message: message)
    }

    public func debug(_ message: String, subsystem: String = "Titik") {
        log(.debug, subsystem: subsystem, message: message)
    }

    public func info(_ message: String, subsystem: String = "Titik") {
        log(.info, subsystem: subsystem, message: message)
    }

    public func warn(_ message: String, subsystem: String = "Titik") {
        log(.warn, subsystem: subsystem, message: message)
    }

    public func error(_ message: String, subsystem: String = "Titik") {
        log(.error, subsystem: subsystem, message: message)
    }
}
