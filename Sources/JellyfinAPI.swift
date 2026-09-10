import Foundation

/// Поверхность API Jellyfin, которой пользуется приложение.
///
/// Отделяет UI и состояние от конкретной реализации клиента: разные версии
/// сервера могут поддерживаться разными реализациями этого протокола.
protocol JellyfinAPI: Sendable {
    func authenticate(serverURL: String, username: String, password: String) async throws -> JellyfinSession

    /// Публичные сведения о сервере — доступны без авторизации.
    func loadServerInfo(serverURL: URL) async throws -> JellyfinServerInfo

    func loadLibrary(
        for session: JellyfinSession,
        progress: @escaping @MainActor @Sendable (Double, String) -> Void
    ) async throws -> LibrarySnapshot

    func loadPlaylistTracks(playlistID: String, session: JellyfinSession) async throws -> [Track]
    func loadArtistTracks(artistID: String, session: JellyfinSession) async throws -> [Track]
    func loadArtistSongCount(artistID: String, session: JellyfinSession) async throws -> Int
    func loadArtistAppearances(artistID: String, session: JellyfinSession) async throws -> [Track]
    func loadArtistAlbums(artistID: String, session: JellyfinSession) async throws -> [Album]
    func loadAlbumTracks(albumID: String, session: JellyfinSession) async throws -> [Track]

    func search(term: String, session: JellyfinSession) async throws -> SearchResults

    func loadInstantMixForTrack(itemID: String, session: JellyfinSession) async throws -> [Track]
    func loadInstantMixForArtist(artistID: String, session: JellyfinSession) async throws -> [Track]
    func loadInstantMixForAlbum(albumID: String, session: JellyfinSession) async throws -> [Track]
    func loadInstantMixForPlaylist(playlistID: String, session: JellyfinSession) async throws -> [Track]

    func playbackContext(for track: Track, session: JellyfinSession) async throws -> PlaybackContext
    func httpHeaders(for session: JellyfinSession) -> [String: String]
    func artworkURL(itemID: String, maxWidth: Int, session: JellyfinSession) -> URL

    func reportPlaybackStart(track: Track, context: PlaybackContext, session: JellyfinSession) async
    func reportPlaybackProgress(
        track: Track,
        context: PlaybackContext,
        session: JellyfinSession,
        position: TimeInterval,
        isPaused: Bool
    ) async
    func reportPlaybackStopped(
        track: Track,
        context: PlaybackContext,
        session: JellyfinSession,
        position: TimeInterval,
        failed: Bool
    ) async

    func setFavorite(itemID: String, isFavorite: Bool, session: JellyfinSession) async throws
}

extension JellyfinAPI {
    func artworkURL(itemID: String, session: JellyfinSession) -> URL {
        artworkURL(itemID: itemID, maxWidth: 1_024, session: session)
    }

    func reportPlaybackStopped(
        track: Track,
        context: PlaybackContext,
        session: JellyfinSession,
        position: TimeInterval
    ) async {
        await reportPlaybackStopped(
            track: track,
            context: context,
            session: session,
            position: position,
            failed: false
        )
    }
}
