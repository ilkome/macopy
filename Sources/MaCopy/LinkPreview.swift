import Foundation
import SwiftData

enum LinkPreviewStatus: String, Codable, Sendable {
    case pending
    case ok
    case failed
    case skipped
}

@Model
final class LinkPreview {
    @Attribute(.unique) var urlHash: String
    var url: String
    var hostname: String?
    var title: String?
    var siteName: String?
    var summary: String?
    var imageData: Data?
    var iconData: Data?
    var fetchedAt: Date
    var statusRaw: String

    var status: LinkPreviewStatus {
        get { LinkPreviewStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        urlHash: String,
        url: String,
        hostname: String? = nil,
        title: String? = nil,
        siteName: String? = nil,
        summary: String? = nil,
        imageData: Data? = nil,
        iconData: Data? = nil,
        fetchedAt: Date = Date(),
        status: LinkPreviewStatus = .pending
    ) {
        self.urlHash = urlHash
        self.url = url
        self.hostname = hostname
        self.title = title
        self.siteName = siteName
        self.summary = summary
        self.imageData = imageData
        self.iconData = iconData
        self.fetchedAt = fetchedAt
        self.statusRaw = status.rawValue
    }
}
