import Foundation
import SwiftUI

@MainActor
final class LibraryNavigationState: ObservableObject {
    @Published var path: [LibraryRoute] = []
}

@MainActor
final class PlaybackProgressState: ObservableObject {
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var signedIn = false
    @Published private(set) var serverInfo: JellyfinServerInfo?
    @Published private(set) var serverInfoError: String?
    @Published var serverURL: String = UserDefaults.standard.string(forKey: AppConfiguration.DefaultsKey.serverURL) ?? "" {
        didSet { UserDefaults.standard.set(serverURL, forKey: AppConfiguration.DefaultsKey.serverURL) }
    }
    @Published var username = ""
    @Published var password = ""
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var selection: SidebarSection = .playlists
    @Published var isPlaying = false
    @Published var currentTrack = Track.empty { didSet { syncSystemPlaybackState() } }
    @Published var queue: [Track] = [] { didSet { syncSystemPlaybackState() } }
    @Published var queueIndex = 0 { didSet { syncSystemPlaybackState() } }
    @Published var isQueueVisible = false
    @Published var isShuffleEnabled = false { didSet { syncSystemPlaybackState() } }
    @Published var repeatMode: PlaybackRepeatMode = .off { didSet { syncSystemPlaybackState() } }
    @Published var playlists: [Playlist] = []
    @Published var artists: [Artist] = []
    @Published var favoriteTracks: [Track] = [] { didSet { syncSystemPlaybackState() } }
    @Published var cacheSizeMB: Int = AppState.storedCacheSizeMB {
        didSet {
            UserDefaults.standard.set(cacheSizeMB, forKey: AppConfiguration.DefaultsKey.cacheSizeMB)
            Task { await artworkCache.setLimitMB(cacheSizeMB) }
        }
    }
    @Published var dateDisplayFormat: DateDisplayFormat = AppState.storedDateDisplayFormat {
        didSet {
            UserDefaults.standard.set(dateDisplayFormat.rawValue, forKey: AppConfiguration.DefaultsKey.dateDisplayFormat)
        }
    }
    @Published var cacheUsageText = "Calculating..."
    @Published var searchResults = SearchResults()
    @Published var isSearching = false
    @Published var selectedPlaylist: Playlist?
    @Published var selectedPlaylistTracks: [Track] = []
    @Published var isLoadingPlaylist = false
    @Published var playlistLoadError: String?
    @Published var selectedArtist: Artist?
    @Published var selectedArtistTracks: [Track] = []
    @Published var selectedArtistAlbums: [Album] = []
    @Published var selectedArtistAppearances: [Track] = []
    @Published var isLoadingArtist = false
    @Published var artistLoadError: String?
    @Published var selectedAlbum: Album?
    @Published var selectedAlbumTracks: [Track] = []
    @Published var isLoadingAlbum = false
    @Published var albumLoadError: String?
    @Published var statusMessage = "Ready"
    @Published var librarySyncProgress: Double?
    @Published var librarySyncMessage = ""

    private let sessionStore = SessionStore()
    let navigation = LibraryNavigationState()
    let playbackProgress = PlaybackProgressState()
    private let client: any JellyfinAPI = JellyfinClient()
    private let playback = PlaybackController()
    private let libraryCache = LibraryCache()
    private let artworkCache = ArtworkCache()
    private let artistSongCountLoader = ArtistSongCountLoader(maxConcurrentRequests: 4)
    private var session: JellyfinSession?
    private var searchTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    private var playlistLoadTask: Task<Void, Never>?
    private var artistLoadTask: Task<Void, Never>?
    private var albumLoadTask: Task<Void, Never>?
    private var queueLoadTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var cacheRestoreTask: Task<Void, Never>?
    private var artistSongCounts: [String: Int] = [:]
    private var artistSongCountTasks: [String: Task<Void, Never>] = [:]
    private var artistIndexByID: [String: Int] = [:]
    private var pendingArtistSongCountUpdates: [String: Int] = [:]
    private var artistSongCountFlushTask: Task<Void, Never>?
    private var librarySyncGeneration = 0

    private static var storedCacheSizeMB: Int {
        let stored = UserDefaults.standard.integer(forKey: AppConfiguration.DefaultsKey.cacheSizeMB)
        return stored == 0 ? AppConfiguration.defaultArtworkCacheSizeMB : stored
    }

    private static var storedDateDisplayFormat: DateDisplayFormat {
        guard let rawValue = UserDefaults.standard.string(forKey: AppConfiguration.DefaultsKey.dateDisplayFormat),
              let format = DateDisplayFormat(rawValue: rawValue)
        else {
            return .year
        }
        return format
    }

    var playbackPosition: TimeInterval {
        get { playbackProgress.position }
        set { playbackProgress.position = newValue }
    }

    var playbackDuration: TimeInterval {
        get { playbackProgress.duration }
        set { playbackProgress.duration = newValue }
    }

    var canPlayOrPause: Bool {
        signedIn && currentTrack.itemID != nil
    }

    var canPlayNext: Bool {
        queueIndex < queue.count - 1 || (repeatMode == .all && queue.count > 1)
    }

    var canPlayPrevious: Bool {
        queueIndex > 0 || (repeatMode == .all && queue.count > 1)
    }

    var canNavigateBack: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !navigation.path.isEmpty
    }

    private init() {
        playback.configureRemoteCommands(
            play: { [weak self] in self?.resumePlayback() },
            pause: { [weak self] in self?.pausePlayback() },
            toggle: { [weak self] in self?.togglePlayback() },
            next: { [weak self] in self?.playNextTrack() },
            previous: { [weak self] in self?.playPreviousTrack() },
            seek: { [weak self] position in self?.seek(to: position) },
            setShuffle: { [weak self] enabled in self?.setShuffle(enabled) },
            setRepeat: { [weak self] mode in self?.repeatMode = mode },
            like: { [weak self] in self?.setCurrentTrackFavorite(true) },
            dislike: { [weak self] in self?.setCurrentTrackFavorite(false) }
        )
        playback.onProgress = { [weak self] position, duration in
            self?.playbackPosition = position.isFinite ? max(0, position) : 0
            self?.playbackDuration = duration.isFinite ? max(0, duration) : 0
        }
        playback.onError = { [weak self] message in
            self?.isPlaying = false
            self?.statusMessage = "Playback failed: \(message)"
        }
        playback.onFinished = { [weak self] in
            guard let self else { return }
            self.isPlaying = false
            if self.repeatMode == .one || (self.repeatMode == .all && self.queue.count == 1) {
                self.play(self.currentTrack)
            } else if self.canPlayNext {
                self.playNextTrack()
            } else {
                self.playbackPosition = self.playbackDuration
                self.statusMessage = "Playback finished"
            }
        }
        syncSystemPlaybackState()
        restoreState()
    }

    func signIn() {
        let trimmedServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty, !trimmedUsername.isEmpty, !password.isEmpty else {
            statusMessage = "Server, username, and password are required"
            return
        }

        signInTask?.cancel()
        let suppliedPassword = password
        statusMessage = "Signing in..."
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let authenticated = try await client.authenticate(
                    serverURL: trimmedServer,
                    username: trimmedUsername,
                    password: suppliedPassword
                )
                try Task.checkCancellation()
                try persistSession(authenticated)
                self.session = authenticated
                self.serverInfo = authenticated.server
                self.serverURL = authenticated.serverURL.absoluteString
                self.username = authenticated.userName
                self.password = ""
                self.signedIn = true
                self.statusMessage = "Loading library..."

                let library = try await self.loadLibrary(for: authenticated)
                try Task.checkCancellation()
                guard self.session?.accessToken == authenticated.accessToken else { return }
                self.apply(library)
                self.statusMessage = "Signed in"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = error.localizedDescription
                self.signedIn = self.session != nil
            }
        }
    }

    @discardableResult
    func signOut() -> Bool {
        do {
            try sessionStore.clear()
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
        cancelSessionTasks()
        stopPlayback()
        session = nil
        serverInfo = nil
        serverInfoError = nil
        signedIn = false
        username = ""
        password = ""
        playlists = []
        artists = []
        favoriteTracks = []
        queue = []
        currentTrack = .empty
        finishLibrarySync()
        statusMessage = "Signed out"
        return true
    }

    func loadArtistSongCountIfNeeded(_ artist: Artist) {
        guard let session, let artistID = artist.itemID else { return }
        if let count = artistSongCounts[artistID] {
            enqueueArtistSongCountUpdate(artistID: artistID, count: count)
            return
        }
        guard artistSongCountTasks[artistID] == nil else { return }

        let accessToken = session.accessToken
        artistSongCountTasks[artistID] = Task { [weak self] in
            guard let self else { return }
            defer { self.artistSongCountTasks[artistID] = nil }
            do {
                let count = try await self.artistSongCountLoader.count(
                    artistID: artistID,
                    session: session,
                    client: self.client
                )
                try Task.checkCancellation()
                guard self.session?.accessToken == accessToken else { return }
                self.artistSongCounts[artistID] = count
                self.enqueueArtistSongCountUpdate(artistID: artistID, count: count)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func clearCache() {
        Task {
            await libraryCache.clear()
            await artworkCache.clear()
            await refreshCacheUsage()
        }
        statusMessage = "Cache cleared"
    }

    func refreshLibrary() {
        guard let session else {
            statusMessage = "Sign in first"
            return
        }

        libraryTask?.cancel()
        let accessToken = session.accessToken
        statusMessage = "Refreshing library..."
        libraryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let library = try await self.loadLibrary(for: session)
                try Task.checkCancellation()
                guard self.session?.accessToken == accessToken else { return }
                self.apply(library)
                self.statusMessage = "Library refreshed"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.session?.accessToken == accessToken else { return }
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func refreshCacheUsage() async {
        let bytes = await artworkCache.currentSizeBytes()
        cacheUsageText = Self.formatByteCount(bytes)
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = SearchResults()
        isSearching = false
    }

    func dismissSearch() {
        guard !searchText.isEmpty else {
            clearSearch()
            return
        }
        searchText = ""
    }

    func navigate(to section: SidebarSection) {
        cancelArtistSongCountLoads()
        dismissSearch()
        navigation.path = []
        closeAlbum()
        closePlaylist()
        closeArtist()
        selection = section
    }

    func updateNavigationPath(_ path: [LibraryRoute]) {
        cancelArtistSongCountLoads()
        let commonPrefixLength = zip(navigation.path, path).prefix { $0 == $1 }.count
        let removedRoutes = navigation.path.dropFirst(commonPrefixLength)
        navigation.path = path
        removedRoutes.reversed().forEach(finishNavigationBack)
    }

    private func finishNavigationBack(_ route: LibraryRoute) {
        switch route {
        case .search:
            dismissSearch()
        case .album:
            guard !navigation.path.contains(where: { if case .album = $0 { true } else { false } }) else { return }
            closeAlbum()
        case .artist:
            guard !navigation.path.contains(where: { if case .artist = $0 { true } else { false } }) else { return }
            closeArtist()
        case .playlist:
            guard !navigation.path.contains(where: { if case .playlist = $0 { true } else { false } }) else { return }
            closePlaylist()
        }
    }

    func enqueue(_ track: Track) {
        queue.append(track)
        statusMessage = "Added to queue"
    }

    func openPlaylist(_ playlist: Playlist) {
        cancelArtistSongCountLoads()
        playlistLoadTask?.cancel()
        selectedPlaylist = playlist
        let route = LibraryRoute.playlist(playlist)
        if navigation.path.last != route {
            navigation.path.append(route)
        }
        selectedPlaylistTracks = []
        playlistLoadError = nil
        guard let session, let playlistID = playlist.itemID else {
            statusMessage = "Playlist is not available"
            playlistLoadError = statusMessage
            return
        }

        isLoadingPlaylist = true
        statusMessage = "Loading playlist..."
        playlistLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await client.loadPlaylistTracks(playlistID: playlistID, session: session)
                try Task.checkCancellation()
                guard self.selectedPlaylist?.itemID == playlistID else { return }
                self.selectedPlaylistTracks = tracks
                self.isLoadingPlaylist = false
                self.playlistLoadError = nil
                self.statusMessage = tracks.isEmpty ? "Playlist is empty" : "Playlist loaded"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.selectedPlaylist?.itemID == playlistID else { return }
                self.isLoadingPlaylist = false
                self.playlistLoadError = error.localizedDescription
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func retryPlaylistLoad() {
        guard let selectedPlaylist else { return }
        openPlaylist(selectedPlaylist)
    }

    func closePlaylist() {
        playlistLoadTask?.cancel()
        playlistLoadTask = nil
        selectedPlaylist = nil
        selectedPlaylistTracks = []
        isLoadingPlaylist = false
        playlistLoadError = nil
    }

    func openArtist(_ artist: Artist) {
        cancelArtistSongCountLoads()
        artistLoadTask?.cancel()
        selectedArtist = artist
        let route = LibraryRoute.artist(artist)
        if navigation.path.last != route {
            navigation.path.append(route)
        }
        selectedArtistTracks = []
        selectedArtistAlbums = []
        selectedArtistAppearances = []
        artistLoadError = nil
        guard let session, let artistID = artist.itemID else {
            statusMessage = "Artist is not available"
            artistLoadError = statusMessage
            return
        }

        isLoadingArtist = true
        statusMessage = "Loading artist..."
        artistLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let tracks = client.loadArtistTracks(artistID: artistID, session: session)
                async let albums = client.loadArtistAlbums(artistID: artistID, session: session)
                async let appearances = client.loadArtistAppearances(artistID: artistID, session: session)
                let loadedTracks = try await tracks
                let loadedAlbums = try await albums
                let loadedAppearances = try await appearances
                let playableTracks = loadedTracks.isEmpty
                    ? await loadTracksFromAlbums(loadedAlbums, session: session)
                    : loadedTracks
                try Task.checkCancellation()
                guard self.selectedArtist?.itemID == artistID else { return }
                self.selectedArtistTracks = playableTracks
                self.selectedArtistAlbums = loadedAlbums
                self.selectedArtistAppearances = loadedAppearances.filter { appearance in
                    !playableTracks.contains(where: { $0.matches(appearance) })
                }
                self.isLoadingArtist = false
                self.artistLoadError = nil
                self.statusMessage = playableTracks.isEmpty ? "No tracks for artist" : "Artist loaded"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.selectedArtist?.itemID == artistID else { return }
                self.isLoadingArtist = false
                self.artistLoadError = error.localizedDescription
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func retryArtistLoad() {
        guard let selectedArtist else { return }
        openArtist(selectedArtist)
    }

    func closeArtist() {
        artistLoadTask?.cancel()
        artistLoadTask = nil
        selectedArtist = nil
        selectedArtistTracks = []
        selectedArtistAlbums = []
        selectedArtistAppearances = []
        isLoadingArtist = false
        artistLoadError = nil
    }

    func openAlbum(_ album: Album) {
        cancelArtistSongCountLoads()
        selectedAlbum = album
        let route = LibraryRoute.album(album)
        if navigation.path.last != route {
            navigation.path.append(route)
        }
        loadAlbumDetails(album)
    }

    private func loadAlbumDetails(_ album: Album) {
        albumLoadTask?.cancel()
        selectedAlbumTracks = []
        albumLoadError = nil
        guard let session, let albumID = album.itemID else {
            statusMessage = "Album is not available"
            albumLoadError = statusMessage
            return
        }

        isLoadingAlbum = true
        statusMessage = "Loading album..."
        albumLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await client.loadAlbumTracks(albumID: albumID, session: session)
                try Task.checkCancellation()
                guard self.selectedAlbum?.itemID == albumID else { return }
                self.selectedAlbumTracks = tracks
                self.isLoadingAlbum = false
                self.albumLoadError = nil
                self.statusMessage = tracks.isEmpty ? "Album is empty" : "Album loaded"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.selectedAlbum?.itemID == albumID else { return }
                self.isLoadingAlbum = false
                self.albumLoadError = error.localizedDescription
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func openAlbum(from track: Track) {
        guard let albumID = track.albumID ?? track.parentID else {
            statusMessage = "Album is not available"
            return
        }

        openAlbum(Album(
            id: albumID,
            itemID: albumID,
            title: track.album,
            artist: track.artist,
            year: nil,
            releaseDate: nil,
            dateCreated: nil,
            genres: [],
            overview: nil,
            trackCount: 0,
            durationText: "",
            artistID: track.artistID
        ))
    }

    func retryAlbumLoad() {
        guard let selectedAlbum else { return }
        loadAlbumDetails(selectedAlbum)
    }

    func closeAlbum() {
        albumLoadTask?.cancel()
        albumLoadTask = nil
        selectedAlbum = nil
        selectedAlbumTracks = []
        isLoadingAlbum = false
        albumLoadError = nil
    }

    func playPlaylist(_ playlist: Playlist) {
        guard let session, let playlistID = playlist.itemID else {
            statusMessage = "Playlist is not available"
            return
        }

        queueLoadTask?.cancel()
        statusMessage = "Loading playlist..."
        queueLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await client.loadPlaylistTracks(playlistID: playlistID, session: session)
                try Task.checkCancellation()
                self.replacePlaybackQueue(with: tracks)
                if let first = tracks.first {
                    self.play(first)
                } else {
                    self.statusMessage = "Playlist is empty"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func playSelectedPlaylist() {
        queueLoadTask?.cancel()
        guard !selectedPlaylistTracks.isEmpty else {
            statusMessage = "Playlist is empty"
            return
        }
        replacePlaybackQueue(with: selectedPlaylistTracks)
        if let first = selectedPlaylistTracks.first {
            play(first)
        }
    }

    func playArtist(_ artist: Artist) {
        guard let session, let artistID = artist.itemID else {
            statusMessage = "Artist is not available"
            return
        }

        queueLoadTask?.cancel()
        statusMessage = "Loading artist..."
        queueLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                var tracks = try await client.loadArtistTracks(artistID: artistID, session: session)
                if tracks.isEmpty {
                    let albums = selectedArtist?.matchesIdentity(artist) == true && !selectedArtistAlbums.isEmpty
                        ? selectedArtistAlbums
                        : try await client.loadArtistAlbums(artistID: artistID, session: session)
                    tracks = await loadTracksFromAlbums(albums, session: session)
                }
                if tracks.isEmpty {
                    tracks = try await client.loadArtistAppearances(artistID: artistID, session: session)
                }
                try Task.checkCancellation()
                self.replacePlaybackQueue(with: tracks)
                if let first = tracks.first {
                    self.play(first)
                } else {
                    self.statusMessage = "No tracks for artist"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func playSelectedArtist() {
        queueLoadTask?.cancel()
        let playableTracks = selectedArtistTracks.isEmpty ? selectedArtistAppearances : selectedArtistTracks
        if playableTracks.isEmpty, let selectedArtist {
            playArtist(selectedArtist)
            return
        }

        guard !playableTracks.isEmpty else {
            statusMessage = "No tracks for artist"
            return
        }
        replacePlaybackQueue(with: playableTracks)
        if let first = playableTracks.first {
            play(first)
        }
    }

    func loadSelectedArtistTracksFromAlbumsIfNeeded() {
        guard selectedArtistTracks.isEmpty,
              !selectedArtistAlbums.isEmpty,
              !isLoadingArtist,
              let session,
              let artistID = selectedArtist?.itemID
        else {
            return
        }

        artistLoadTask?.cancel()
        isLoadingArtist = true
        statusMessage = "Loading artist tracks..."
        artistLoadTask = Task { [weak self] in
            guard let self else { return }
            let tracks = await loadTracksFromAlbums(selectedArtistAlbums, session: session)
            guard !Task.isCancelled, self.selectedArtist?.itemID == artistID else { return }
            self.selectedArtistTracks = tracks
            self.isLoadingArtist = false
            self.statusMessage = tracks.isEmpty ? "No tracks for artist" : "Artist tracks loaded"
        }
    }

    func playSelectedAlbum() {
        queueLoadTask?.cancel()
        guard !selectedAlbumTracks.isEmpty else {
            statusMessage = "Album is empty"
            return
        }
        replacePlaybackQueue(with: selectedAlbumTracks)
        if let first = selectedAlbumTracks.first {
            play(first)
        }
    }

    func playAlbum(_ album: Album) {
        guard let session, let albumID = album.itemID else {
            statusMessage = "Album is not available"
            return
        }

        queueLoadTask?.cancel()
        statusMessage = "Loading album..."
        queueLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await client.loadAlbumTracks(albumID: albumID, session: session)
                try Task.checkCancellation()
                self.replacePlaybackQueue(with: tracks)
                if let first = tracks.first {
                    self.play(first)
                } else {
                    self.statusMessage = "Album is empty"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func playFavorites(_ tracks: [Track]? = nil) {
        queueLoadTask?.cancel()
        let tracksToPlay = tracks ?? favoriteTracks
        guard !tracksToPlay.isEmpty else {
            statusMessage = "Favorites are empty"
            return
        }

        replacePlaybackQueue(with: tracksToPlay)
        if let first = tracksToPlay.first {
            play(first)
        }
    }

    func startStation(from track: Track) {
        guard let session, let itemID = track.itemID else {
            statusMessage = "Station is not available"
            return
        }

        startStation { try await self.client.loadInstantMixForTrack(itemID: itemID, session: session) }
    }

    func startStation(from artist: Artist) {
        guard let session, let artistID = artist.itemID else {
            statusMessage = "Station is not available"
            return
        }

        startStation { try await self.client.loadInstantMixForArtist(artistID: artistID, session: session) }
    }

    func startStation(from album: Album) {
        guard let session, let albumID = album.itemID else {
            statusMessage = "Station is not available"
            return
        }

        startStation { try await self.client.loadInstantMixForAlbum(albumID: albumID, session: session) }
    }

    func startStation(from playlist: Playlist) {
        guard let session, let playlistID = playlist.itemID else {
            statusMessage = "Station is not available"
            return
        }

        startStation { try await self.client.loadInstantMixForPlaylist(playlistID: playlistID, session: session) }
    }

    private func startStation(_ loader: @escaping () async throws -> [Track]) {
        queueLoadTask?.cancel()
        statusMessage = "Starting station..."
        queueLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await loader()
                try Task.checkCancellation()
                if let first = tracks.first {
                    self.replacePlaybackQueue(with: tracks)
                    self.play(first)
                } else {
                    self.statusMessage = "Station returned no tracks"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func play(_ track: Track) {
        playTask?.cancel()
        artworkTask?.cancel()
        currentTrack = track
        if let index = queue.firstIndex(where: { $0.matches(track) }) {
            queueIndex = index
        }
        guard let session, track.itemID != nil else {
            isPlaying = false
            return
        }

        statusMessage = "Loading \(track.title)..."
        playTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await playback.play(track: track, session: session, client: client)
                try Task.checkCancellation()
                guard self.currentTrack.matches(track) else { return }
                self.artworkTask = Task { [weak self] in
                    guard let self,
                          let url = await self.artworkURL(for: track, maxWidth: 512),
                          !Task.isCancelled
                    else { return }
                    await playback.loadNowPlayingArtwork(from: url, for: track)
                }
                self.currentTrack = track
                self.isPlaying = true
                self.playbackDuration = track.duration
                self.statusMessage = "Playing \(track.title)"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.currentTrack.matches(track) else { return }
                self.isPlaying = false
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        guard let session else {
            isPlaying.toggle()
            statusMessage = isPlaying ? "Playing" : "Paused"
            return
        }
        playback.toggle(session: session, client: client)
        isPlaying = playback.isPlaying
        statusMessage = isPlaying ? "Playing" : "Paused"
    }

    private func resumePlayback() {
        guard !isPlaying else { return }
        guard let session else { return }
        playback.setPlaying(true, session: session, client: client)
        isPlaying = true
        statusMessage = "Playing"
    }

    private func pausePlayback() {
        guard isPlaying else { return }
        guard let session else { return }
        playback.setPlaying(false, session: session, client: client)
        isPlaying = false
        statusMessage = "Paused"
    }

    func seek(to position: TimeInterval) {
        guard let session, playbackDuration > 0 else { return }
        let bounded = min(max(position, 0), playbackDuration)
        playbackPosition = bounded
        playback.seek(to: bounded, session: session, client: client)
    }

    func playNextTrack() {
        guard canPlayNext else { return }
        guard let nextIndex = PlaybackQueueState.nextIndex(in: queue, from: queueIndex, wrapping: repeatMode == .all) else { return }
        queueIndex = nextIndex
        let next = queue[queueIndex]
        play(next)
        statusMessage = "Next track"
    }

    func playPreviousTrack() {
        guard canPlayPrevious else { return }
        guard let previousIndex = PlaybackQueueState.previousIndex(in: queue, from: queueIndex, wrapping: repeatMode == .all) else { return }
        queueIndex = previousIndex
        let previous = queue[queueIndex]
        play(previous)
        statusMessage = "Previous track"
    }

    func stopPlayback() {
        playTask?.cancel()
        playTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        guard let session else {
            isPlaying = false
            return
        }
        playback.stop(session: session, client: client)
        isPlaying = false
        playbackPosition = 0
        playbackDuration = 0
    }

    func clearQueue() {
        queueLoadTask?.cancel()
        queueLoadTask = nil
        queue.removeAll()
        queueIndex = 0
        stopPlayback()
        statusMessage = "Queue cleared"
    }

    func shuffleQueue() {
        guard queue.count > 1 else { return }
        queue.shuffle()
        syncQueueIndexToCurrentTrack()
        statusMessage = "Queue shuffled"
    }

    func toggleQueueVisibility() {
        isQueueVisible.toggle()
    }

    func toggleShuffle() {
        setShuffle(!isShuffleEnabled)
    }

    private func setShuffle(_ enabled: Bool) {
        guard isShuffleEnabled != enabled else { return }
        isShuffleEnabled = enabled
        if enabled {
            queue.shuffle()
            if let index = queue.firstIndex(where: { $0.matches(currentTrack) }) {
                queueIndex = index
            }
        }
        statusMessage = isShuffleEnabled ? "Shuffle on" : "Shuffle off"
    }

    func moveQueueItem(from source: Int, to destination: Int) {
        guard queue.indices.contains(source), queue.indices.contains(destination), source != destination else { return }
        let track = queue.remove(at: source)
        queue.insert(track, at: destination)
        syncQueueIndexToCurrentTrack()
        statusMessage = "Queue reordered"
    }

    func removeQueueItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removedCurrent = index == queueIndex
        queue.remove(at: index)
        if queue.isEmpty {
            queueIndex = 0
            stopPlayback()
        } else if removedCurrent {
            queueIndex = min(index, queue.count - 1)
            play(queue[queueIndex])
        } else {
            syncQueueIndexToCurrentTrack()
        }
        statusMessage = "Removed from queue"
    }

    func openArtist(id: String? = nil, named name: String) {
        guard let id, !id.isEmpty else {
            statusMessage = "Artist is not available"
            return
        }

        let candidates = artists + searchResults.artists + (selectedArtist.map { [$0] } ?? [])
        if let artist = candidates.first(where: { $0.itemID == id }) {
            openArtist(artist)
            return
        }

        openArtist(Artist(id: id, itemID: id, name: name, genre: "Music", songCount: 0))
    }

    func isFavorite(_ track: Track) -> Bool {
        favoriteTracks.contains(where: { $0.matches(track) })
    }

    func isCurrentTrack(_ track: Track) -> Bool {
        currentTrack.matches(track)
    }

    func toggleFavorite(_ track: Track) {
        setFavorite(track, isFavorite: !isFavorite(track))
    }

    private func setCurrentTrackFavorite(_ isFavorite: Bool) {
        guard currentTrack.itemID != nil else { return }
        setFavorite(currentTrack, isFavorite: isFavorite)
    }

    private func setFavorite(_ track: Track, isFavorite shouldFavorite: Bool) {
        guard isFavorite(track) != shouldFavorite else { return }
        if let index = favoriteTracks.firstIndex(where: { $0.matches(track) }) {
            favoriteTracks.remove(at: index)
            statusMessage = "Removed from favorites"
        } else {
            var copy = track
            copy.isFavorite = true
            favoriteTracks.insert(copy, at: 0)
            statusMessage = "Added to favorites"
        }
        syncFavorite(track, isFavorite: shouldFavorite)
    }

    private func syncFavorite(_ track: Track, isFavorite: Bool) {
        guard let session, let itemID = track.itemID else { return }
        Task {
            do {
                try await client.setFavorite(itemID: itemID, isFavorite: isFavorite, session: session)
            } catch {
                await MainActor.run {
                    self.revertFavorite(track, attemptedFavorite: isFavorite)
                    self.statusMessage = "Favorite sync failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func revertFavorite(_ track: Track, attemptedFavorite: Bool) {
        if attemptedFavorite {
            favoriteTracks.removeAll { $0.matches(track) }
        } else {
            var copy = track
            copy.isFavorite = true
            if !favoriteTracks.contains(where: { $0.matches(copy) }) {
                favoriteTracks.insert(copy, at: 0)
            }
        }
    }

    func artworkURL(for track: Track, maxWidth: Int = 1_024) async -> URL? {
        guard let session else { return nil }
        guard let artworkID = ArtworkReference.itemID(for: track) else { return nil }
        return await artworkCache.localURL(
            for: ArtworkReference.cacheKey(itemID: artworkID, maxWidth: maxWidth),
            remoteURL: client.artworkURL(itemID: artworkID, maxWidth: maxWidth, session: session)
        )
    }

    func artworkURL(for playlist: Playlist, maxWidth: Int = 1_024) async -> URL? {
        guard let session, let itemID = playlist.itemID else { return nil }
        return await artworkCache.localURL(for: ArtworkReference.cacheKey(itemID: itemID, maxWidth: maxWidth), remoteURL: client.artworkURL(itemID: itemID, maxWidth: maxWidth, session: session))
    }

    func artworkURL(for artist: Artist, maxWidth: Int = 1_024) async -> URL? {
        guard let session, let itemID = artist.itemID else { return nil }
        return await artworkCache.localURL(for: ArtworkReference.cacheKey(itemID: itemID, maxWidth: maxWidth), remoteURL: client.artworkURL(itemID: itemID, maxWidth: maxWidth, session: session))
    }

    func artworkURL(for album: Album, maxWidth: Int = 1_024) async -> URL? {
        guard let session, let itemID = album.itemID else { return nil }
        return await artworkCache.localURL(for: ArtworkReference.cacheKey(itemID: itemID, maxWidth: maxWidth), remoteURL: client.artworkURL(itemID: itemID, maxWidth: maxWidth, session: session))
    }

    private func restoreState() {
        let restored: JellyfinSession?
        do {
            restored = try sessionStore.load()
        } catch {
            statusMessage = error.localizedDescription
            return
        }
        guard let restored else {
            return
        }

        session = restored
        serverInfo = restored.server
        signedIn = true
        serverURL = restored.serverURL.absoluteString
        username = restored.userName
        statusMessage = "Loading library..."

        Task { [weak self] in
            await self?.refreshServerInfo(for: restored)
        }

        cacheRestoreTask = Task { [weak self] in
            await self?.restoreCachedLibrary(for: restored)
        }
        libraryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let library = try await self.loadLibrary(for: restored)
                try Task.checkCancellation()
                guard self.session?.accessToken == restored.accessToken else { return }
                self.cacheRestoreTask?.cancel()
                self.cacheRestoreTask = nil
                self.apply(library)
                self.statusMessage = "Signed in"
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.session?.accessToken == restored.accessToken else { return }
                self.statusMessage = error.localizedDescription
            }
        }
    }

    private func restoreCachedLibrary(for session: JellyfinSession) async {
        guard let cached = await libraryCache.load() else { return }
        guard !Task.isCancelled, self.session?.accessToken == session.accessToken else { return }
        var cachedArtists = cached.artists
        for index in cachedArtists.indices {
            cachedArtists[index].songCount = -1
        }
        let cachedFavorites = cached.favoriteTracks.allSatisfy { $0.artistID != nil }
            ? cached.favoriteTracks
            : []
        self.apply(LibrarySnapshot(playlists: cached.playlists, artists: cachedArtists, favoriteTracks: cachedFavorites))
    }

    private func loadLibrary(for session: JellyfinSession) async throws -> LibrarySnapshot {
        librarySyncGeneration += 1
        let generation = librarySyncGeneration
        librarySyncProgress = 0
        librarySyncMessage = "Starting library sync..."
        defer {
            if librarySyncGeneration == generation {
                finishLibrarySync()
            }
        }
        return try await client.loadLibrary(for: session) { [weak self] progress, message in
            guard let self, self.librarySyncGeneration == generation else { return }
            self.librarySyncProgress = min(max(progress, 0), 1)
            self.librarySyncMessage = message
        }
    }

    private func finishLibrarySync() {
        librarySyncProgress = nil
        librarySyncMessage = ""
    }

    /// Сервер могли обновить между запусками — перечитываем версию и сохраняем её в сессии.
    func refreshServerInfo() async {
        guard let current = session else { return }
        await refreshServerInfo(for: current)
    }

    /// Первый запрос после запуска может упасть, пока macOS не выдала доступ к локальной сети,
    /// поэтому один раз повторяем попытку.
    private func loadServerInfoRetrying(serverURL: URL) async throws -> JellyfinServerInfo {
        do {
            return try await client.loadServerInfo(serverURL: serverURL)
        } catch {
            try await Task.sleep(for: .seconds(2))
            return try await client.loadServerInfo(serverURL: serverURL)
        }
    }

    private func refreshServerInfo(for restored: JellyfinSession) async {
        let info: JellyfinServerInfo
        do {
            info = try await loadServerInfoRetrying(serverURL: restored.serverURL)
        } catch {
            guard session?.accessToken == restored.accessToken else { return }
            serverInfoError = error.localizedDescription
            return
        }
        guard session?.accessToken == restored.accessToken else { return }
        serverInfo = info
        serverInfoError = nil
        guard var updated = session, updated.server != info else { return }
        updated.server = info
        session = updated
        try? persistSession(updated)
    }

    private func persistSession(_ session: JellyfinSession) throws {
        try sessionStore.save(session)
    }

    private func replacePlaybackQueue(with tracks: [Track]) {
        queue = tracks
        queueIndex = 0
        if isShuffleEnabled {
            queue.shuffle()
        }
    }

    private func syncQueueIndexToCurrentTrack() {
        if let index = PlaybackQueueState.currentIndex(in: queue, for: currentTrack) {
            queueIndex = index
        } else {
            queueIndex = min(queueIndex, max(queue.count - 1, 0))
        }
    }

    private func syncSystemPlaybackState() {
        playback.updateRemoteState(
            queueIndex: queueIndex,
            queueCount: queue.count,
            hasTrack: currentTrack.itemID != nil,
            isFavorite: isFavorite(currentTrack),
            shuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode,
            canPlayNext: canPlayNext,
            canPlayPrevious: canPlayPrevious
        )
    }

    private func loadTracksFromAlbums(_ albums: [Album], session: JellyfinSession) async -> [Track] {
        var loadedTracks: [Track] = []
        for album in albums.prefix(8) {
            guard let albumID = album.itemID else { continue }
            guard let tracks = try? await client.loadAlbumTracks(albumID: albumID, session: session) else {
                continue
            }
            loadedTracks.append(contentsOf: tracks)
            if loadedTracks.count >= 50 {
                break
            }
        }
        return Array(loadedTracks.prefix(50))
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSearchNavigation(for: term)
        guard !term.isEmpty, let session else {
            clearSearch()
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let results = try await self?.client.search(term: term, session: session) ?? SearchResults()
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.searchResults = results
                    self?.isSearching = false
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.isSearching = false
                    self?.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func updateSearchNavigation(for term: String) {
        if term.isEmpty {
            navigation.path.removeAll { route in
                if case .search = route { return true }
                return false
            }
        } else if navigation.path.last != .search {
            navigation.path.append(.search)
        }
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        playlists = snapshot.playlists
        artists = LibraryProjection.artists(snapshot.artists, applying: artistSongCounts)
        artistIndexByID = LibraryProjection.artistIndexByID(artists)
        favoriteTracks = snapshot.favoriteTracks

        let payload = LibraryCachePayload(
            playlists: snapshot.playlists,
            artists: snapshot.artists,
            favoriteTracks: snapshot.favoriteTracks,
            updatedAt: Date()
        )
        Task {
            await libraryCache.save(payload)
        }
    }

    private func cancelSessionTasks() {
        librarySyncGeneration += 1
        signInTask?.cancel()
        libraryTask?.cancel()
        playlistLoadTask?.cancel()
        artistLoadTask?.cancel()
        albumLoadTask?.cancel()
        queueLoadTask?.cancel()
        playTask?.cancel()
        artworkTask?.cancel()
        cacheRestoreTask?.cancel()
        searchTask?.cancel()
        artistSongCountTasks.values.forEach { $0.cancel() }
        artistSongCountFlushTask?.cancel()
        Task { await artistSongCountLoader.reset() }
        signInTask = nil
        libraryTask = nil
        playlistLoadTask = nil
        artistLoadTask = nil
        albumLoadTask = nil
        queueLoadTask = nil
        playTask = nil
        artworkTask = nil
        cacheRestoreTask = nil
        searchTask = nil
        artistSongCountTasks.removeAll()
        artistSongCounts.removeAll()
        artistIndexByID.removeAll()
        pendingArtistSongCountUpdates.removeAll()
        artistSongCountFlushTask = nil
    }

    private func enqueueArtistSongCountUpdate(artistID: String, count: Int) {
        pendingArtistSongCountUpdates[artistID] = count
        guard artistSongCountFlushTask == nil else { return }
        artistSongCountFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.flushArtistSongCountUpdates()
        }
    }

    private func flushArtistSongCountUpdates() {
        let updates = pendingArtistSongCountUpdates
        pendingArtistSongCountUpdates.removeAll()
        artistSongCountFlushTask = nil
        guard !updates.isEmpty else { return }

        var updatedArtists = artists
        for (artistID, count) in updates {
            if let index = artistIndexByID[artistID], updatedArtists.indices.contains(index) {
                updatedArtists[index].songCount = count
            }
        }
        artists = updatedArtists

        var updatedSearchArtists = searchResults.artists
        for index in updatedSearchArtists.indices {
            guard let artistID = updatedSearchArtists[index].itemID,
                  let count = updates[artistID] else { continue }
            updatedSearchArtists[index].songCount = count
        }
        searchResults.artists = updatedSearchArtists

        if let artistID = selectedArtist?.itemID, let count = updates[artistID] {
            selectedArtist?.songCount = count
        }
    }

    private func cancelArtistSongCountLoads() {
        artistSongCountTasks.values.forEach { $0.cancel() }
        artistSongCountTasks.removeAll()
        Task { await artistSongCountLoader.cancelPending() }
    }

    private static func formatByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
