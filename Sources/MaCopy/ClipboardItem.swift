import Foundation
import SwiftData

enum ClipKind: String, Codable, Sendable {
    case text, code, url, color, image
}

@Model
final class ClipboardItem {
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
    var isFavorite: Bool = false

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
        byteSize: Int = 0
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
    }
}
