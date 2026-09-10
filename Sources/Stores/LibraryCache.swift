import Foundation

struct LibraryCachePayload: Codable {
    var playlists: [Playlist]
    var artists: [Artist]
    var favoriteTracks: [Track]
    var updatedAt: Date
}

actor LibraryCache {
    private let fileURL: URL

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folderURL = baseURL.appendingPathComponent("Jellia", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        fileURL = folderURL.appendingPathComponent("library-cache.json")
    }

    func load() -> LibraryCachePayload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LibraryCachePayload.self, from: data)
    }

    func save(_ payload: LibraryCachePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
