import Foundation
import GRDB

enum LinkPreviewStatus: String, Codable, Sendable {
    case pending
    case ok
    case failed
    case skipped
}

struct LinkPreviewRecord: Codable, Identifiable, Hashable, Sendable {
    var urlHash: String
    var url: String
    var hostname: String?
    var title: String?
    var siteName: String?
    var summary: String?
    var imageData: Data?
    var iconData: Data?
    var fetchedAt: Date
    var statusRaw: String

    var id: String { urlHash }

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

extension LinkPreviewRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "link_previews"

    enum Columns {
        static let urlHash = Column(CodingKeys.urlHash)
        static let url = Column(CodingKeys.url)
        static let hostname = Column(CodingKeys.hostname)
        static let title = Column(CodingKeys.title)
        static let siteName = Column(CodingKeys.siteName)
        static let summary = Column(CodingKeys.summary)
        static let imageData = Column(CodingKeys.imageData)
        static let iconData = Column(CodingKeys.iconData)
        static let fetchedAt = Column(CodingKeys.fetchedAt)
        static let statusRaw = Column(CodingKeys.statusRaw)
    }
}
