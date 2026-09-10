import SwiftUI

struct PlaylistTableView: View {
    @ObservedObject var appState: AppState
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: AppSpacing.lg)]

    var body: some View {
        let playlists = appState.playlists.filter { $0.matchesSearch(appState.searchText) }
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppSpacing.lg) {
                ForEach(playlists) { playlist in
                    PlaylistCardView(playlist: playlist, appState: appState)
                }
            }
            .padding()
            .padding(.bottom, AppSpacing.playerOverlayInset)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct PlaylistCardView: View {
    let playlist: Playlist
    @ObservedObject var appState: AppState

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ZStack(alignment: .bottomLeading) {
                RemoteArtworkView(
                    artworkID: playlist.itemID ?? playlist.id,
                    fallbackSymbol: AppIcon.playlists,
                    fallbackGradient: AppFallback.playlist,
                    maxPixelSize: 512
                ) {
                    await appState.artworkURL(for: playlist, maxWidth: 512)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                if isHovering {
                    ArtworkActionButton(icon: AppIcon.play, help: "Play") {
                        appState.playPlaylist(playlist)
                    }
                    .padding(AppSpacing.xs)
                    .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.012 : 1)
        .shadow(color: .black.opacity(isHovering ? AppOpacity.subtle : AppOpacity.hidden), radius: isHovering ? 12 : 0, y: 5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            appState.openPlaylist(playlist)
        }
    }

    private var subtitle: String {
        var parts = ["\(playlist.trackCount) tracks"]
        if !playlist.durationText.isEmpty {
            parts.append(playlist.durationText)
        }
        return parts.joined(separator: " - ")
    }
}

struct PlaylistDetailView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                if appState.isLoadingPlaylist {
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }

                if let playlist = appState.selectedPlaylist {
                    HStack(alignment: .top, spacing: AppSpacing.hero) {
                        RemoteArtworkView(
                            artworkID: playlist.itemID ?? playlist.id,
                            fallbackSymbol: AppIcon.playlists,
                            fallbackGradient: AppFallback.playlist
                        ) {
                            await appState.artworkURL(for: playlist)
                        }
                        .frame(width: AppSize.detailArtwork, height: AppSize.detailArtwork)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                        VStack(alignment: .leading, spacing: AppSpacing.control) {
                            Text(playlist.name)
                                .font(.system(size: 38, weight: .bold))
                                .lineLimit(2)

                            PlaylistMetaView(playlist: playlist)

                            HStack(spacing: AppSpacing.control) {
                                HeaderIconButton(icon: AppIcon.play, help: "Play") {
                                    appState.playSelectedPlaylist()
                                }
                                .disabled(appState.selectedPlaylistTracks.isEmpty)

                                HeaderIconButton(icon: AppIcon.station, help: "Start Station") {
                                    appState.startStation(from: playlist)
                                }
                                .disabled(playlist.itemID == nil)
                            }
                            .padding(.top, AppSpacing.xxs)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, AppSpacing.xs)
                    }
                }

                Group {
                    if appState.isLoadingPlaylist {
                        LoadingRowsView()
                    } else if let error = appState.playlistLoadError {
                        LoadErrorView(message: error) {
                            appState.retryPlaylistLoad()
                        }
                    } else if appState.selectedPlaylistTracks.isEmpty {
                        Text("No tracks in this playlist.")
                            .foregroundStyle(.secondary)
                    } else {
                        PlaylistTracksView(appState: appState)
                    }
                }
            }
            .padding()
            .padding(.bottom, AppSpacing.playerOverlayInset)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct PlaylistMetaView: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Label("\(playlist.trackCount) tracks", systemImage: AppIcon.playlists)
            if !playlist.durationText.isEmpty {
                Text("-")
                Text(playlist.durationText)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct PlaylistTracksView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            ForEach(Array(appState.selectedPlaylistTracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(
                    track: track,
                    appState: appState,
                    showAlbum: true,
                    leadingText: String(index + 1)
                )
            }
        }
    }
}
