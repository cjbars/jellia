import SwiftUI

struct AlbumDetailView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                if appState.isLoadingAlbum {
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }

                if let album = appState.selectedAlbum {
                    HStack(alignment: .top, spacing: AppSpacing.hero) {
                        RemoteArtworkView(
                            artworkID: album.itemID ?? album.id,
                            fallbackSymbol: AppIcon.album,
                            fallbackGradient: AppFallback.album
                        ) {
                            await appState.artworkURL(for: album)
                        }
                        .frame(width: AppSize.detailArtwork, height: AppSize.detailArtwork)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                        VStack(alignment: .leading, spacing: AppSpacing.control) {
                            Text(album.title)
                                .font(.system(size: 38, weight: .bold))
                                .lineLimit(2)

                            AlbumMetaView(album: album, appState: appState, dateFormat: appState.dateDisplayFormat)
                            AlbumGenresView(genres: album.genres)

                            HStack(spacing: AppSpacing.control) {
                                HeaderIconButton(icon: AppIcon.play, help: "Play") {
                                    appState.playSelectedAlbum()
                                }
                                .disabled(appState.selectedAlbumTracks.isEmpty)

                                HeaderIconButton(icon: AppIcon.station, help: "Start Station") {
                                    appState.startStation(from: album)
                                }
                                .disabled(album.itemID == nil)
                            }
                            .padding(.top, AppSpacing.xxs)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, AppSpacing.xs)
                    }
                }

                if let overview = appState.selectedAlbum?.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
                    Text(overview)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: 720, alignment: .leading)
                }

                Group {
                    if appState.isLoadingAlbum {
                        LoadingRowsView()
                    } else if let error = appState.albumLoadError {
                        LoadErrorView(message: error) {
                            appState.retryAlbumLoad()
                        }
                    } else if appState.selectedAlbumTracks.isEmpty {
                        Text("No tracks in this album.")
                            .foregroundStyle(.secondary)
                    } else {
                        AlbumTracksView(appState: appState)
                    }
                }
            }
            .padding()
            .padding(.bottom, AppSpacing.playerOverlayInset)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct AlbumMetaView: View {
    let album: Album
    @ObservedObject var appState: AppState
    let dateFormat: DateDisplayFormat

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: AppIcon.artists)
            ArtistTextLink(name: album.artist, artistID: album.artistID, appState: appState)
            if let releaseText = album.releaseText(format: dateFormat) {
                Text("-")
                Text(releaseText)
            }
            if album.trackCount > 0 {
                Text("-")
                Text("\(album.trackCount) tracks")
            }
            if !album.durationText.isEmpty {
                Text("-")
                Text(album.durationText)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct AlbumGenresView: View {
    let genres: [String]

    var body: some View {
        if !genres.isEmpty {
            HStack(spacing: AppSpacing.xs) {
                ForEach(genres.prefix(4), id: \.self) { genre in
                    Text(genre)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(Color.secondary.opacity(AppOpacity.subtle), in: Capsule())
                }
            }
        }
    }
}

private struct AlbumTracksView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let showDiscNumbers = Set(appState.selectedAlbumTracks.compactMap(\.discNumber)).count > 1
        VStack(spacing: AppSpacing.xxs) {
            ForEach(appState.selectedAlbumTracks) { track in
                TrackRow(
                    track: track,
                    appState: appState,
                    showAlbum: false,
                    leadingText: track.albumPositionText(showDisc: showDiscNumbers)
                )
            }
        }
    }
}
