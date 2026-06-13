import Foundation
import GRDB

/// Join row tying a clip to a folder (many-to-many). Composite primary key
/// (folderId, itemId) enforces uniqueness of a membership.
struct FolderItemRecord: Codable, Hashable, Sendable {
    var folderId: UUID
    var itemId: UUID
    var addedAt: Date

    init(folderId: UUID, itemId: UUID, addedAt: Date = Date()) {
        self.folderId = folderId
        self.itemId = itemId
        self.addedAt = addedAt
    }
}

extension FolderItemRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder_items"

    enum Columns {
        static let folderId = Column(CodingKeys.folderId)
        static let itemId = Column(CodingKeys.itemId)
        static let addedAt = Column(CodingKeys.addedAt)
    }
}
