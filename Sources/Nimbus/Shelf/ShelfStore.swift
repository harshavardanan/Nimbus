import AppKit

struct ShelfItem: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String { url.lastPathComponent }
}

/// Files parked on the notch. Only the paths are remembered, never the file contents.
@MainActor
final class ShelfStore: ObservableObject {
    private static let key = "nimbus.shelf.paths.v1"

    @Published private(set) var items: [ShelfItem] = []

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        // Files that were moved or deleted since last time quietly drop off.
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(ShelfItem.init)
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.insert(ShelfItem(url: url), at: 0)
        }
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func loadDemo() {
        items = ["Invoice.pdf", "photo.png", "notes.txt"].map { ShelfItem(url: URL(fileURLWithPath: "/tmp/\($0)")) }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: Self.key)
    }
}
