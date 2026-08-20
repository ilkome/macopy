import Foundation
import GRDB

/// Join row tying a clip to a folder (many-to-many). Composite primary key
/// (folderId, itemId) enforces uniqueness of a membership.
struct FolderItemRecord: Codable, Hashable, Sendable {
    var folderId: UUID
    var itemId: UUID
    var addedAt: Date
    var lastUsedAt: Date

    init(folderId: UUID, itemId: UUID, addedAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.folderId = folderId
        self.itemId = itemId
        self.addedAt = addedAt
        self.lastUsedAt = lastUsedAt ?? addedAt
    }
}

extension FolderItemRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder_items"

    enum Columns {
        static let folderId = Column(CodingKeys.folderId)
        static let itemId = Column(CodingKeys.itemId)
        static let addedAt = Column(CodingKeys.addedAt)
        static let lastUsedAt = Column(CodingKeys.lastUsedAt)
    }
}
