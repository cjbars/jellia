import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var appState: AppState
    @State private var focusedKind: SearchResultKind?
    private let artistCardWidth: CGFloat = 224
    private let artistColumns: [GridItem] = [GridItem(.adaptive(minimum: 224, maximum: 224), spacing: AppSpacing.lg)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                HStack {
                    Text(focusedKind?.title ?? "Search Results")
                        .font(.title2.bold())
                    Spacer()
                    if focusedKind != nil {
                        Button("All Results") {
                            focusedKind = nil
                        }
                    }
                    if appState.isSearching {
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.searchResults.isEmpty && !appState.isSearching {
                    Text("No results for \"\(appState.searchText)\".")
                        .foregroundStyle(.secondary)
                }

                if shouldShow(.tracks), !appState.searchResults.tracks.isEmpty {
                    SearchSectionHeader(
                        title: "Tracks",
                        count: appState.searchResults.tracks.count,
                        showAll: focusedKind == nil && appState.searchResults.tracks.count > 8
                    ) {
                        focusedKind = .tracks
                    }
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(visibleTracks) { track in
                            TrackRow(track: track, appState: appState)
                        }
                    }
                }

                if shouldShow(.artists), !appState.searchResults.artists.isEmpty {
                    SearchSectionHeader(
                        title: "Artists",
                        count: appState.searchResults.artists.count,
                        showAll: focusedKind == nil && appState.searchResults.artists.count > 8
                    ) {
                        focusedKind = .artists
                    }
                    LazyVGrid(columns: artistColumns, spacing: AppSpacing.lg) {
                        ForEach(visibleArtists) { artist in
                            ArtistCardView(
                                artist: artist,
                                width: artistCardWidth,
                                artworkURL: { await appState.artworkURL(for: artist, maxWidth: 512) },
                                onOpen: { appState.openArtist(artist) },
                                onPlay: { appState.playArtist(artist) },
                                onStartStation: { appState.startStation(from: artist) },
                                onLoadSongCount: { appState.loadArtistSongCountIfNeeded(artist) }
                            )
                        }
                    }
                }

                if shouldShow(.albums), !appState.searchResults.albums.isEmpty {
                    SearchSectionHeader(
                        title: "Albums",
                        count: appState.searchResults.albums.count,
                        showAll: focusedKind == nil && appState.searchResults.albums.count > 8
                    ) {
                        focusedKind = .albums
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppSpacing.sm)], spacing: AppSpacing.sm) {
                        ForEach(visibleAlbums) { album in
                            AlbumCardView(
                                album: album,
                                dateFormat: appState.dateDisplayFormat,
                                artworkURL: { await appState.artworkURL(for: album, maxWidth: 512) },
                                onOpen: { appState.openAlbum(album) },
                                onPlay: { appState.playAlbum(album) }
                            )
                        }
                    }
                }

                if shouldShow(.playlists), !appState.searchResults.playlists.isEmpty {
                    SearchSectionHeader(
                        title: "Playlists",
                        count: appState.searchResults.playlists.count,
                        showAll: focusedKind == nil && appState.searchResults.playlists.count > 8
                    ) {
                        focusedKind = .playlists
                    }
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(visiblePlaylists) { playlist in
                            HStack {
                                RemoteArtworkView(
                                    artworkID: playlist.itemID ?? playlist.id,
                                    fallbackSymbol: AppIcon.playlists,
                                    fallbackGradient: AppFallback.playlist,
                                    size: 38,
                                    maxPixelSize: 128
                                ) {
                                    await appState.artworkURL(for: playlist, maxWidth: 128)
                                }
                                .frame(width: 44, height: 44)

                                VStack(alignment: .leading) {
                                    Text(playlist.name).font(.headline)
                                    Text("\(playlist.trackCount) tracks")
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Play") { appState.playPlaylist(playlist) }
                            }
                            .padding(AppSpacing.row)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                        }
                    }
                }
            }
            .padding()
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.playerOverlayInset)
        }
        .scrollContentBackground(.hidden)
        .onChange(of: appState.searchText) { _, _ in
            focusedKind = nil
        }
    }

    private var visibleTracks: [Track] {
        visible(appState.searchResults.tracks, kind: .tracks)
    }

    private var visibleArtists: [Artist] {
        visible(appState.searchResults.artists, kind: .artists)
    }

    private var visibleAlbums: [Album] {
        visible(appState.searchResults.albums, kind: .albums)
    }

    private var visiblePlaylists: [Playlist] {
        visible(appState.searchResults.playlists, kind: .playlists)
    }

    private func shouldShow(_ kind: SearchResultKind) -> Bool {
        focusedKind == nil || focusedKind == kind
    }

    private func visible<T>(_ items: [T], kind: SearchResultKind) -> [T] {
        focusedKind == kind ? items : Array(items.prefix(8))
    }
}

private enum SearchResultKind {
    case tracks
    case artists
    case albums
    case playlists

    var title: String {
        switch self {
        case .tracks: return "Track Results"
        case .artists: return "Artist Results"
        case .albums: return "Album Results"
        case .playlists: return "Playlist Results"
        }
    }
}

private struct SearchSectionHeader: View {
    let title: String
    let count: Int
    var showAll = false
    var onShowAll: () -> Void = {}

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Text("\(count)")
                .foregroundStyle(.secondary)
            Spacer()
            if showAll {
                Button("Show All", action: onShowAll)
                    .buttonStyle(.borderless)
            }
        }
    }
}
