import Foundation
import TitikCore

public typealias CTitikPluginInitFn = @convention(c) () -> Int32
public typealias CTitikPluginQueryFn = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?, Int32) -> Int32
public typealias CTitikPluginExecuteFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
public typealias CTitikPluginShutdownFn = @convention(c) () -> Void

public struct CTitikPlugin {
    public var id: UnsafePointer<CChar>?
    public var name: UnsafePointer<CChar>?
    public var version: UnsafePointer<CChar>?
    public var description: UnsafePointer<CChar>?
    public var short_bang: UnsafePointer<CChar>?
    public var `init`: CTitikPluginInitFn?
    public var query: CTitikPluginQueryFn?
    public var execute: CTitikPluginExecuteFn?
    public var shutdown: CTitikPluginShutdownFn?
}

public typealias CTitikPluginEntryFn = @convention(c) () -> UnsafeRawPointer?

public struct PluginItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: String
    public let actionPayload: String
    public let scoreBoost: Int
    public let pluginId: String

    public init(
        id: String,
        title: String,
        subtitle: String,
        category: String,
        actionPayload: String,
        scoreBoost: Int = 0,
        pluginId: String = ""
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.actionPayload = actionPayload
        self.scoreBoost = scoreBoost
        self.pluginId = pluginId
    }

    public static let cItemSize = 772

    private static func boundedString(from rawPtr: UnsafeRawPointer, offset: Int, maxLength: Int) -> String {
        let ptr = rawPtr.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
        let buffer = UnsafeBufferPointer(start: ptr, count: maxLength)
        if let nullIndex = buffer.firstIndex(of: 0) {
            let slice = buffer.prefix(upTo: nullIndex)
            return String(decoding: slice, as: UTF8.self)
        } else {
            return String(decoding: buffer, as: UTF8.self)
        }
    }

    public static func fromRawMemory(_ ptr: UnsafeRawPointer, pluginId: String) -> PluginItem {
        let idStr = boundedString(from: ptr, offset: 0, maxLength: 64)
        let titleStr = boundedString(from: ptr, offset: 64, maxLength: 128)
        let subtitleStr = boundedString(from: ptr, offset: 192, maxLength: 256)
        let catStr = boundedString(from: ptr, offset: 448, maxLength: 64)
        let payloadStr = boundedString(from: ptr, offset: 512, maxLength: 256)
        let boost = ptr.advanced(by: 768).assumingMemoryBound(to: Int32.self).pointee

        return PluginItem(
            id: idStr,
            title: titleStr,
            subtitle: subtitleStr,
            category: catStr.isEmpty ? "Plugin" : catStr,
            actionPayload: payloadStr,
            scoreBoost: Int(boost),
            pluginId: pluginId
        )
    }
}

public struct PluginDescriptor: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let shortBang: String
    public let path: String

    public init(id: String, name: String, version: String, description: String, shortBang: String = "", path: String) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.shortBang = shortBang
        self.path = path
    }
}
