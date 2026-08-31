import Foundation
import TitikCore
@_exported import TitikPluginKit

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
