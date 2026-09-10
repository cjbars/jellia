import Foundation

enum JellyfinError: LocalizedError {
    case invalidServerURL
    case network(URL, URLError)
    case missingAccessToken
    case missingUserID
    case missingItemID
    case badResponse
    case httpStatus(Int, String)
    case noMediaSource
    case emptyInstantMix

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "Invalid server URL"
        case let .network(url, error):
            if error.code == .notConnectedToInternet, Self.isLocalNetworkURL(url) {
                return "Local network access is blocked for \(url.host() ?? url.absoluteString). Enable Jellia in System Settings > Privacy & Security > Local Network."
            }
            return "Cannot connect to \(url.absoluteString): \(error.localizedDescription)"
        case .missingAccessToken: return "Missing Jellyfin access token"
        case .missingUserID: return "Missing Jellyfin user ID"
        case .missingItemID: return "Missing Jellyfin item ID"
        case .badResponse: return "Unexpected Jellyfin response"
        case let .httpStatus(status, body):
            if status == 401 {
                return "Jellyfin rejected the login. Check username and password."
            }
            return "Jellyfin returned HTTP \(status): \(body)"
        case .noMediaSource: return "No playable media source"
        case .emptyInstantMix: return "Jellyfin returned an empty station"
        }
    }

    private static func isLocalNetworkURL(_ url: URL) -> Bool {
        guard let host = url.host() else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 172 && (16...31).contains(octets[1])
    }
}

private enum JellyfinFields {
    static let track = "MediaSources,ParentId"
    static let trackPosition = track
    static let favoriteTrack = track + ",AlbumId,AlbumArtists,ArtistItems"
    static let album = "ChildCount,DateCreated,Genres,Overview"
    static let search = track + ",ChildCount,DateCreated,Genres,Overview,ItemCounts"
    static let playlist = "ChildCount"
}

private enum JellyfinLimit {
    static let playlistTracks = "200"
    static let artistTracks = "50"
    static let albums = "100"
    static let albumTracks = "300"
    static let search = "60"
    static let libraryPage = "100"
}

final class JellyfinClient: JellyfinAPI {
    private let session = JellyfinNetworking.shared.session
    private let clientName = AppConfiguration.name
    private let version = AppConfiguration.version
    private let deviceName = ProcessInfo.processInfo.hostName
    private let deviceID: String

    init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: AppConfiguration.DefaultsKey.deviceID) {
            deviceID = stored
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: AppConfiguration.DefaultsKey.deviceID)
            deviceID = generated
        }
    }

    func authenticate(serverURL: String, username: String, password: String) async throws -> JellyfinSession {
        guard let baseURL = normalizedBaseURL(serverURL) else {
            throw JellyfinError.invalidServerURL
        }

        let url = baseURL.appendingPathComponent("Users/AuthenticateByName")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader(accessToken: nil), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw JellyfinError.network(url, error)
        }
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(JellyfinAuthResponse.self, from: data)
        guard let accessToken = decoded.accessToken else {
            throw JellyfinError.badResponse
        }

        let userID = decoded.user?.id ?? decoded.sessionInfo?.userId
        guard let userID else {
            throw JellyfinError.missingUserID
        }

        return JellyfinSession(
            serverURL: baseURL,
            userID: userID,
            userName: decoded.user?.name ?? username,
            accessToken: accessToken,
            deviceID: deviceID,
            server: try? await loadServerInfo(serverURL: baseURL)
        )
    }

    func loadServerInfo(serverURL: URL) async throws -> JellyfinServerInfo {
        let url = try makeURL(path: "System/Info/Public", queryItems: [], baseURL: serverURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await sessionData(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(JellyfinPublicSystemInfoDTO.self, from: data)
        return JellyfinServerInfo(
            name: decoded.serverName,
            productName: decoded.productName,
            version: decoded.version.flatMap(ServerVersion.init),
            rawVersion: decoded.version
        )
    }

    func loadLibrary(
        for session: JellyfinSession,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> LibrarySnapshot {
        await progress(0.05, "Syncing playlists...")
        let playlists = try await loadPlaylists(for: session)

        await progress(0.15, "Syncing artists...")
        let artists = try await loadArtists(for: session) { completed, total in
            let denominator = max(total ?? completed, 1)
            let fraction = min(Double(completed) / Double(denominator), 1)
            let countText = total.map { "\(completed)/\($0)" } ?? "\(completed)"
            progress(0.15 + fraction * 0.70, "Syncing artists \(countText)...")
        }

        await progress(0.90, "Syncing favorites...")
        let favorites = try await loadFavorites(for: session)
        await progress(1, "Library synced")
        return LibrarySnapshot(
            playlists: playlists,
            artists: artists,
            favoriteTracks: favorites
        )
    }

    func loadPlaylistTracks(playlistID: String, session: JellyfinSession) async throws -> [Track] {
        let response: JellyfinItemsResponse = try await get(
            path: "Playlists/\(playlistID)/Items",
            queryItems: [
                URLQueryItem(name: "UserId", value: session.userID),
                URLQueryItem(name: "Fields", value: JellyfinFields.track),
                URLQueryItem(name: "SortBy", value: "PlaylistIndex"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Limit", value: JellyfinLimit.playlistTracks)
            ],
            session: session
        )
        return response.items.compactMap(track(from:))
    }

    func loadArtistTracks(artistID: String, session: JellyfinSession) async throws -> [Track] {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "userId", value: session.userID),
                URLQueryItem(name: "ArtistIds", value: artistID),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: JellyfinFields.track),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Limit", value: JellyfinLimit.artistTracks)
            ],
            session: session
        )
        return response.items.compactMap(track(from:))
    }

    func loadArtistSongCount(artistID: String, session: JellyfinSession) async throws -> Int {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "UserId", value: session.userID),
                URLQueryItem(name: "ArtistIds", value: artistID),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Limit", value: "0"),
                URLQueryItem(name: "EnableImages", value: "false"),
                URLQueryItem(name: "EnableUserData", value: "false"),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true")
            ],
            session: session
        )
        return response.totalRecordCount ?? 0
    }

    func loadArtistAppearances(artistID: String, session: JellyfinSession) async throws -> [Track] {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "userId", value: session.userID),
                URLQueryItem(name: "ContributingArtistIds", value: artistID),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: JellyfinFields.track),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Limit", value: JellyfinLimit.artistTracks)
            ],
            session: session
        )
        return response.items.compactMap(track(from:))
    }

    func loadArtistAlbums(artistID: String, session: JellyfinSession) async throws -> [Album] {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "userId", value: session.userID),
                URLQueryItem(name: "AlbumArtistIds", value: artistID),
                URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: JellyfinFields.album),
                URLQueryItem(name: "SortBy", value: "ProductionYear,SortName"),
                URLQueryItem(name: "SortOrder", value: "Descending"),
                URLQueryItem(name: "Limit", value: JellyfinLimit.albums)
            ],
            session: session
        )
        return response.items.compactMap(album(from:))
    }

    func loadAlbumTracks(albumID: String, session: JellyfinSession) async throws -> [Track] {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "userId", value: session.userID),
                URLQueryItem(name: "ParentId", value: albumID),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "false"),
                URLQueryItem(name: "Fields", value: JellyfinFields.trackPosition),
                URLQueryItem(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Limit", value: JellyfinLimit.albumTracks)
            ],
            session: session
        )
        return response.items.compactMap(track(from:))
    }

    func search(term: String, session: JellyfinSession) async throws -> SearchResults {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "userId", value: session.userID),
                URLQueryItem(name: "SearchTerm", value: term),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio,MusicArtist,MusicAlbum,Playlist"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: JellyfinFields.search),
                URLQueryItem(name: "Limit", value: JellyfinLimit.search)
            ],
            session: session
        )

        var results = SearchResults()
        for item in response.items {
            switch item.type {
            case "Audio":
                if let track = track(from: item) {
                    results.tracks.append(track)
                }
            case "MusicArtist":
                if let artist = artist(from: item) {
                    results.artists.append(artist)
                }
            case "MusicAlbum":
                if let album = album(from: item) {
                    results.albums.append(album)
                }
            case "Playlist":
                if let playlist = playlist(from: item) {
                    results.playlists.append(playlist)
                }
            default:
                continue
            }
        }
        return results
    }

    func loadInstantMixForTrack(itemID: String, session: JellyfinSession) async throws -> [Track] {
        try await loadInstantMix(path: "Songs/\(itemID)/InstantMix", session: session)
    }

    func loadInstantMixForArtist(artistID: String, session: JellyfinSession) async throws -> [Track] {
        try await loadInstantMix(path: "Artists/\(artistID)/InstantMix", session: session)
    }

    func loadInstantMixForAlbum(albumID: String, session: JellyfinSession) async throws -> [Track] {
        try await loadInstantMix(path: "Albums/\(albumID)/InstantMix", session: session)
    }

    func loadInstantMixForPlaylist(playlistID: String, session: JellyfinSession) async throws -> [Track] {
        try await loadInstantMix(path: "Playlists/\(playlistID)/InstantMix", session: session)
    }

    func playbackContext(for track: Track, session: JellyfinSession) async throws -> PlaybackContext {
        guard let itemID = track.itemID else {
            throw JellyfinError.missingItemID
        }

        let playbackInfo = try await getPlaybackInfo(itemID: itemID, session: session)
        guard let source = playbackInfo.mediaSources?.first else {
            throw JellyfinError.noMediaSource
        }

        let streamURL: URL
        if let transcodingURL = source.transcodingUrl, let resolved = resolvedURL(transcodingURL, baseURL: session.serverURL) {
            streamURL = resolved
        } else {
            streamURL = audioStreamURL(itemID: itemID, source: source, session: session)
        }

        return PlaybackContext(
            streamURL: streamURL,
            itemID: itemID,
            playSessionID: playbackInfo.playSessionID,
            mediaSourceID: source.id ?? source.mediaSourceId,
            duration: track.duration > 0 ? track.duration : nil
        )
    }

    private func authorizationHeader(accessToken: String?) -> String {
        var parts = [
            #"Client="\#(clientName)""#,
            #"Device="\#(deviceName)""#,
            #"DeviceId="\#(deviceID)""#,
            #"Version="\#(version)""#
        ]
        if let accessToken, !accessToken.isEmpty {
            parts.append(#"Token="\#(accessToken)""#)
        }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private func authorizationHeaders(accessToken: String?) -> [String: String] {
        let header = authorizationHeader(accessToken: accessToken)
        return [
            "Authorization": header,
            "X-Emby-Authorization": header
        ]
    }

    func httpHeaders(for session: JellyfinSession) -> [String: String] {
        authorizationHeaders(accessToken: session.accessToken)
    }

    private func applyAuthorizationHeaders(to request: inout URLRequest, accessToken: String?) {
        for (key, value) in authorizationHeaders(accessToken: accessToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    func artworkURL(itemID: String, maxWidth: Int, session: JellyfinSession) -> URL {
        let boundedWidth = min(max(maxWidth, 64), 1_024)
        var components = URLComponents(url: session.serverURL.appendingPathComponent("Items/\(itemID)/Images/Primary"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "format", value: "jpg"),
            URLQueryItem(name: "quality", value: boundedWidth <= 512 ? "85" : "90"),
            URLQueryItem(name: "maxHeight", value: String(boundedWidth)),
            URLQueryItem(name: "maxWidth", value: String(boundedWidth))
        ]
        return components?.url ?? session.serverURL.appendingPathComponent("Items/\(itemID)/Images/Primary")
    }

    func reportPlaybackStart(track: Track, context: PlaybackContext, session: JellyfinSession) async {
        let report = JellyfinPlaybackReportStart(
            itemID: context.itemID,
            playSessionID: context.playSessionID,
            mediaSourceID: context.mediaSourceID,
            positionTicks: 0,
            isPaused: false,
            playMethod: "DirectPlay"
        )
        await post(path: "Sessions/Playing", body: report, session: session)
    }

    func reportPlaybackProgress(track: Track, context: PlaybackContext, session: JellyfinSession, position: TimeInterval, isPaused: Bool) async {
        let report = JellyfinPlaybackReportProgress(
            itemID: context.itemID,
            playSessionID: context.playSessionID,
            mediaSourceID: context.mediaSourceID,
            positionTicks: ticks(from: position),
            isPaused: isPaused,
            canSeek: true
        )
        await post(path: "Sessions/Playing/Progress", body: report, session: session)
    }

    func reportPlaybackStopped(track: Track, context: PlaybackContext, session: JellyfinSession, position: TimeInterval, failed: Bool) async {
        let report = JellyfinPlaybackReportStop(
            itemID: context.itemID,
            playSessionID: context.playSessionID,
            mediaSourceID: context.mediaSourceID,
            positionTicks: ticks(from: position),
            failed: failed
        )
        await post(path: "Sessions/Playing/Stopped", body: report, session: session)
    }

    func setFavorite(itemID: String, isFavorite: Bool, session: JellyfinSession) async throws {
        let path = "UserFavoriteItems/\(itemID)"
        let queryItems = [URLQueryItem(name: "userId", value: session.userID)]
        if isFavorite {
            try await postChecked(path: path, queryItems: queryItems, body: EmptyBody(), session: session)
        } else {
            try await delete(path: path, queryItems: queryItems, session: session)
        }
    }

    private func loadFavorites(for session: JellyfinSession) async throws -> [Track] {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "userId", value: session.userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Filters", value: "IsFavorite"),
                URLQueryItem(name: "Fields", value: JellyfinFields.favoriteTrack),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Limit", value: JellyfinLimit.libraryPage)
            ],
            session: session
        )
        return response.items.compactMap { item in
            guard let id = item.id, let name = item.name else { return nil }
            let artist = item.albumArtist ?? item.artists?.first ?? "Unknown Artist"
            let sourceID = item.mediaSources?.first?.id ?? item.mediaSources?.first?.mediaSourceId
            return Track(
                id: id,
                itemID: id,
                title: name,
                artist: artist,
                album: item.album ?? "Unknown Album",
                duration: seconds(from: item.runTimeTicks),
                isFavorite: item.isFavorite ?? false,
                mediaSourceID: sourceID,
                playSessionID: nil,
                albumID: item.albumID,
                parentID: item.parentID,
                artistID: item.albumArtists?.first?.id ?? item.artistItems?.first?.id
            )
        }
    }

    private func loadInstantMix(path: String, session: JellyfinSession) async throws -> [Track] {
        let response: JellyfinItemsResponse = try await get(
            path: path,
            queryItems: [
                URLQueryItem(name: "UserId", value: session.userID),
                URLQueryItem(name: "Fields", value: JellyfinFields.track),
                URLQueryItem(name: "Limit", value: JellyfinLimit.libraryPage)
            ],
            session: session
        )
        let tracks = response.items.compactMap(track(from:))
        guard !tracks.isEmpty else {
            throw JellyfinError.emptyInstantMix
        }
        return tracks
    }

    private func loadPlaylists(for session: JellyfinSession) async throws -> [Playlist] {
        let response: JellyfinItemsResponse = try await get(
            path: "Items",
            queryItems: [
                URLQueryItem(name: "userId", value: session.userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "Fields", value: JellyfinFields.playlist),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "Limit", value: JellyfinLimit.libraryPage)
            ],
            session: session
        )
        return response.items.compactMap(playlist(from:))
    }

    private func loadArtists(
        for session: JellyfinSession,
        progress: @escaping @MainActor @Sendable (Int, Int?) -> Void
    ) async throws -> [Artist] {
        try await loadPagedItems(
            path: "Artists",
            baseQueryItems: [
                URLQueryItem(name: "UserId", value: session.userID),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
                URLQueryItem(name: "EnableTotalRecordCount", value: "true")
            ],
            limit: 500,
            session: session,
            progress: progress
        )
        .compactMap(artist(from:))
    }

    private func loadPagedItems(
        path: String,
        baseQueryItems: [URLQueryItem],
        limit: Int,
        session: JellyfinSession,
        progress: @escaping @MainActor @Sendable (Int, Int?) -> Void
    ) async throws -> [JellyfinItemDTO] {
        var allItems: [JellyfinItemDTO] = []
        var startIndex = 0

        while true {
            let response: JellyfinItemsResponse = try await get(
                path: path,
                queryItems: baseQueryItems + [
                    URLQueryItem(name: "StartIndex", value: String(startIndex)),
                    URLQueryItem(name: "Limit", value: String(limit))
                ],
                session: session
            )
            allItems.append(contentsOf: response.items)
            await progress(allItems.count, response.totalRecordCount)

            if let total = response.totalRecordCount {
                guard !response.items.isEmpty, allItems.count < total else {
                    return allItems
                }
            } else {
                guard response.items.count == limit else {
                    return allItems
                }
            }
            guard !response.items.isEmpty else {
                return allItems
            }
            startIndex += response.items.count
        }
    }

    private func playlist(from item: JellyfinItemDTO) -> Playlist? {
        guard let id = item.id, let name = item.name else { return nil }
        return Playlist(
            id: id,
            itemID: id,
            name: name,
            trackCount: item.childCount ?? 0,
            durationText: runtimeText(from: item.runTimeTicks)
        )
    }

    private func artist(from item: JellyfinItemDTO) -> Artist? {
        guard let id = item.id, let name = item.name else { return nil }
        return Artist(
            id: id,
            itemID: id,
            name: name,
            genre: "Music",
            songCount: -1
        )
    }

    private func album(from item: JellyfinItemDTO) -> Album? {
        guard let id = item.id, let name = item.name else { return nil }
        return Album(
            id: id,
            itemID: id,
            title: name,
            artist: item.albumArtist ?? item.artists?.joined(separator: ", ") ?? "Unknown Artist",
            year: item.productionYear,
            releaseDate: item.premiereDate,
            dateCreated: item.dateCreated,
            genres: item.genres ?? [],
            overview: item.overview,
            trackCount: item.childCount ?? 0,
            durationText: runtimeText(from: item.runTimeTicks),
            artistID: item.albumArtists?.first?.id ?? item.artistItems?.first?.id
        )
    }

    private func track(from item: JellyfinItemDTO) -> Track? {
        guard let id = item.id, let name = item.name else { return nil }
        let artist = item.albumArtist ?? item.artists?.first ?? "Unknown Artist"
        let sourceID = item.mediaSources?.first?.id ?? item.mediaSources?.first?.mediaSourceId
        return Track(
            id: id,
            itemID: id,
            title: name,
            artist: artist,
            album: item.album ?? "Unknown Album",
            duration: seconds(from: item.runTimeTicks),
            isFavorite: item.isFavorite ?? false,
            mediaSourceID: sourceID,
            playSessionID: nil,
            albumID: item.albumID,
            parentID: item.parentID,
            trackNumber: item.indexNumber,
            discNumber: item.parentIndexNumber,
            artistID: item.albumArtists?.first?.id ?? item.artistItems?.first?.id
        )
    }

    private func getPlaybackInfo(itemID: String, session: JellyfinSession) async throws -> JellyfinPlaybackInfoResponse {
        let request = JellyfinPlaybackInfoRequest(
            userID: session.userID,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: false
        )
        return try await postForResponse(
            path: "Items/\(itemID)/PlaybackInfo",
            body: request,
            session: session
        )
    }

    private func audioStreamURL(itemID: String, source: JellyfinMediaSourceDTO, session: JellyfinSession) -> URL {
        var components = URLComponents(url: session.serverURL.appendingPathComponent("Audio/\(itemID)/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: source.id ?? source.mediaSourceId),
            URLQueryItem(name: "api_key", value: session.accessToken)
        ].compactMap { query in
            if query.value == nil { return nil }
            return query
        }
        return components?.url ?? session.serverURL.appendingPathComponent("Audio/\(itemID)/stream")
    }

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = [], session: JellyfinSession) async throws -> T {
        let url = try makeURL(path: path, queryItems: queryItems, baseURL: session.serverURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthorizationHeaders(to: &request, accessToken: session.accessToken)
        let (data, response) = try await sessionData(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Encodable>(path: String, body: T, session: JellyfinSession) async {
        do {
            let url = try makeURL(path: path, queryItems: [], baseURL: session.serverURL)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            applyAuthorizationHeaders(to: &request, accessToken: session.accessToken)
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await sessionData(for: request)
            try validate(response: response, data: data)
        } catch {
            return
        }
    }

    private func postForResponse<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        session: JellyfinSession
    ) async throws -> Response {
        let url = try makeURL(path: path, queryItems: [], baseURL: session.serverURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorizationHeaders(to: &request, accessToken: session.accessToken)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await sessionData(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func postChecked<T: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: T,
        session: JellyfinSession
    ) async throws {
        let url = try makeURL(path: path, queryItems: queryItems, baseURL: session.serverURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorizationHeaders(to: &request, accessToken: session.accessToken)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await sessionData(for: request)
        try validate(response: response, data: data)
    }

    private func delete(path: String, queryItems: [URLQueryItem] = [], session: JellyfinSession) async throws {
        let url = try makeURL(path: path, queryItems: queryItems, baseURL: session.serverURL)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyAuthorizationHeaders(to: &request, accessToken: session.accessToken)
        let (data, response) = try await sessionData(for: request)
        try validate(response: response, data: data)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem], baseURL: URL) throws -> URL {
        guard let url = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw JellyfinError.badResponse
        }
        var components = url
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let resolved = components.url else {
            throw JellyfinError.badResponse
        }
        return resolved
    }

    private func normalizedBaseURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme,
           scheme == "http" || scheme == "https" {
            return components.url
        }

        let hostCandidate = trimmed
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? trimmed
        let scheme = isLocalHost(hostCandidate) ? "http" : "https"
        return URLComponents(string: "\(scheme)://\(trimmed)")?.url
    }

    private func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        return octets.count == 4 && octets[0] == 172 && (16...31).contains(octets[1])
    }

    private func resolvedURL(_ value: String, baseURL: URL) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JellyfinError.badResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw JellyfinError.httpStatus(httpResponse.statusCode, responseSummary(from: data))
        }
    }

    private func responseSummary(from data: Data) -> String {
        let text = String(decoding: data.prefix(300), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "empty response" : text
    }

    private func sessionData(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw JellyfinError.badResponse
        }

        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw JellyfinError.network(url, error)
        }
    }

    private func seconds(from ticks: Int64?) -> TimeInterval {
        guard let ticks else { return 0 }
        return TimeInterval(ticks) / 10_000_000
    }

    private func ticks(from seconds: TimeInterval) -> Int64 {
        PlaybackTime.ticks(from: seconds)
    }

    private func runtimeText(from ticks: Int64?) -> String {
        let totalSeconds = Int(seconds(from: ticks).rounded())
        guard totalSeconds > 0 else { return "—" }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
