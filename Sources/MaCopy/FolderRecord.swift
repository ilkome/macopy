import Foundation
import GRDB

/// User-created folder. Membership lives in the `folder_items` join table
/// (`FolderItemRecord`) - a clip can belong to many folders, and a folder can be empty.
struct FolderRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var sortIndex: Int

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}

extension FolderRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folders"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let createdAt = Column(CodingKeys.createdAt)
        static let sortIndex = Column(CodingKeys.sortIndex)
    }
}
