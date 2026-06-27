import Foundation
import AppKit

@MainActor
class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()

    @Published var favorites: [FavoriteDestination] = []

    private let key = "FastTransfer.Favorites"

    private init() {
        load()
    }

    func add(url: URL, name: String? = nil) {
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let label = name ?? url.lastPathComponent
        let fav = FavoriteDestination(name: label, path: url.path, bookmarkData: bookmark)
        if !favorites.contains(where: { $0.path == url.path }) {
            favorites.append(fav)
            save()
        }
    }

    func remove(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    func rename(id: UUID, newName: String) {
        if let idx = favorites.firstIndex(where: { $0.id == id }) {
            favorites[idx].name = newName
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FavoriteDestination].self, from: data) else { return }
        favorites = decoded
    }
}
