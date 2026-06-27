import Foundation

struct FavoriteDestination: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data?

    init(id: UUID = UUID(), name: String, path: String, bookmarkData: Data? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
    }

    var url: URL? {
        if let data = bookmarkData {
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        return URL(fileURLWithPath: path)
    }
}
