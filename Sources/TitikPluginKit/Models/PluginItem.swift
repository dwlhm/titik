import Foundation

public struct PluginItem: Identifiable, Equatable, Sendable, Codable {
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
}
