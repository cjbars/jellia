import Foundation

actor ArtworkCache {
    private let baseDirectory: URL
    private var limitBytes: Int

    init() {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folderURL = baseURL.appendingPathComponent("Jellia/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        baseDirectory = folderURL
        let storedLimit = UserDefaults.standard.integer(forKey: AppConfiguration.DefaultsKey.cacheSizeMB)
        let limitMB = storedLimit == 0 ? AppConfiguration.defaultArtworkCacheSizeMB : storedLimit
        limitBytes = max(limitMB, 1) * 1_024 * 1_024
    }

    func cachedURL(for itemID: String) -> URL {
        baseDirectory.appendingPathComponent(itemID).appendingPathExtension("jpg")
    }

    func localURL(for itemID: String, remoteURL: URL) async -> URL {
        await cachedLocalURL(for: itemID, remoteURL: remoteURL) ?? remoteURL
    }

    func cachedLocalURL(for itemID: String, remoteURL: URL) async -> URL? {
        let cached = cachedURL(for: itemID)
        if FileManager.default.fileExists(atPath: cached.path) {
            guard isImageFile(cached) else {
                try? FileManager.default.removeItem(at: cached)
                return await cachedLocalURL(for: itemID, remoteURL: remoteURL)
            }
            touch(cached)
            return cached
        }
        do {
            let (data, response) = try await JellyfinNetworking.shared.session.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  isImageData(data)
            else {
                return nil
            }
            try data.write(to: cached, options: [.atomic])
            touch(cached)
            evictIfNeeded()
        } catch {
            return nil
        }
        return cached
    }

    func setLimitMB(_ limitMB: Int) {
        limitBytes = max(limitMB, 1) * 1_024 * 1_024
        evictIfNeeded()
    }

    func currentSizeBytes() -> Int {
        cachedFiles().reduce(0) { $0 + $1.size }
    }

    func clear() {
        try? FileManager.default.removeItem(at: baseDirectory)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return false }
        return isImageData(data)
    }

    private func isImageData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let bytes = [UInt8](data.prefix(12))
        let isJPEG = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
        let isPNG = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
        let isWebP = bytes.count >= 12
            && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50
        return isJPEG || isPNG || isWebP
    }

    private func evictIfNeeded() {
        let files = cachedFiles()
        let totalSize = files.reduce(0) { $0 + $1.size }
        guard totalSize > limitBytes else { return }

        var removable = files.sorted { $0.accessDate < $1.accessDate }
        var currentSize = totalSize
        while currentSize > limitBytes, let file = removable.first {
            removable.removeFirst()
            try? FileManager.default.removeItem(at: file.url)
            currentSize -= file.size
        }
    }

    private func cachedFiles() -> [(url: URL, size: Int, accessDate: Date)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else {
                return nil
            }

            return (
                url: url,
                size: values.fileSize ?? 0,
                accessDate: values.contentAccessDate ?? values.contentModificationDate ?? .distantPast
            )
        }
    }
}
