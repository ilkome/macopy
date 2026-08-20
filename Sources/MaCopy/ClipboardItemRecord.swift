import Foundation
import GRDB

enum ClipKind: String, Codable, Sendable {
    case text, code, url, color, image
}

struct ClipboardItemRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var contentHash: String
    var kindRaw: String
    var text: String?
    var preview: String
    var imagePath: String?
    var imageWidth: Int
    var imageHeight: Int
    var ocrText: String?
    var sourceAppBundleId: String?
    var sourceAppName: String?
    var sourceAppIconPath: String?
    var sourceFilePath: String?
    var byteSize: Int
    var isFavorite: Bool
    var comment: String?
    var copyCount: Int64
    var pasteCount: Int64
    var lastFavoriteUsedAt: Date
    var lastSiteUsedAt: Date

    var kind: ClipKind { ClipKind(rawValue: kindRaw) ?? .text }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        contentHash: String,
        kind: ClipKind,
        text: String? = nil,
        preview: String,
        imagePath: String? = nil,
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        ocrText: String? = nil,
        sourceAppBundleId: String? = nil,
        sourceAppName: String? = nil,
        sourceAppIconPath: String? = nil,
        sourceFilePath: String? = nil,
        byteSize: Int = 0,
        isFavorite: Bool = false,
        comment: String? = nil,
        copyCount: Int64 = 1,
        pasteCount: Int64 = 0,
        lastFavoriteUsedAt: Date? = nil,
        lastSiteUsedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contentHash = contentHash
        self.kindRaw = kind.rawValue
        self.text = text
        self.preview = preview
        self.imagePath = imagePath
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.ocrText = ocrText
        self.sourceAppBundleId = sourceAppBundleId
        self.sourceAppName = sourceAppName
        self.sourceAppIconPath = sourceAppIconPath
        self.sourceFilePath = sourceFilePath
        self.byteSize = byteSize
        self.isFavorite = isFavorite
        self.comment = comment
        self.copyCount = copyCount
        self.pasteCount = pasteCount
        self.lastFavoriteUsedAt = lastFavoriteUsedAt ?? updatedAt
        self.lastSiteUsedAt = lastSiteUsedAt ?? updatedAt
    }
}

extension ClipboardItemRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_items"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let contentHash = Column(CodingKeys.contentHash)
        static let kindRaw = Column(CodingKeys.kindRaw)
        static let text = Column(CodingKeys.text)
        static let preview = Column(CodingKeys.preview)
        static let imagePath = Column(CodingKeys.imagePath)
        static let imageWidth = Column(CodingKeys.imageWidth)
        static let imageHeight = Column(CodingKeys.imageHeight)
        static let ocrText = Column(CodingKeys.ocrText)
        static let sourceAppBundleId = Column(CodingKeys.sourceAppBundleId)
        static let sourceAppName = Column(CodingKeys.sourceAppName)
        static let sourceAppIconPath = Column(CodingKeys.sourceAppIconPath)
        static let sourceFilePath = Column(CodingKeys.sourceFilePath)
        static let byteSize = Column(CodingKeys.byteSize)
        static let isFavorite = Column(CodingKeys.isFavorite)
        static let comment = Column(CodingKeys.comment)
        static let copyCount = Column(CodingKeys.copyCount)
        static let pasteCount = Column(CodingKeys.pasteCount)
        static let lastFavoriteUsedAt = Column(CodingKeys.lastFavoriteUsedAt)
        static let lastSiteUsedAt = Column(CodingKeys.lastSiteUsedAt)
    }
}
