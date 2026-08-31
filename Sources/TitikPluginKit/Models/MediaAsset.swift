import Foundation

public enum MediaAssetType: String, Codable, Sendable {
    case image
    case map
    case diagram
    case codeSnippet
}

public struct MediaAsset: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let type: MediaAssetType
    public let title: String
    public let urlString: String?
    public let content: String?
    public let language: String?
    public let latitude: Double?
    public let longitude: Double?
    public let altText: String?

    public init(
        id: String = UUID().uuidString,
        type: MediaAssetType,
        title: String,
        urlString: String? = nil,
        content: String? = nil,
        language: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altText: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.urlString = urlString
        self.content = content
        self.language = language
        self.latitude = latitude
        self.longitude = longitude
        self.altText = altText
    }
}
