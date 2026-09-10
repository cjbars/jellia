import SwiftUI

struct TrackRow: View {
    let track: Track
    @ObservedObject var appState: AppState
    var showAlbum = true
    var showArtwork = false
    var leadingText: String?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if showArtwork {
                RemoteArtworkView(
                    artworkID: track.itemID ?? track.id,
                    fallbackSymbol: AppIcon.track,
                    fallbackGradient: AppFallback.track,
                    size: 44,
                    maxPixelSize: 128
                ) {
                    await appState.artworkURL(for: track, maxWidth: 128)
                }
                .frame(width: 44, height: 44)
            }

            Button {
                appState.play(track)
            } label: {
                Group {
                    if isHovering {
                        Image(systemName: AppIcon.play)
                    } else if appState.isCurrentTrack(track) && appState.isPlaying {
                        PlayingIndicatorView(isPlaying: true)
                    } else if let leadingText {
                        Text(leadingText)
                            .font(.caption.monospacedDigit())
                    } else {
                        Image(systemName: AppIcon.track)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle((isHovering || appState.isCurrentTrack(track)) ? Color.accentColor : Color.secondary)
            .opacity(isHovering || appState.isCurrentTrack(track) || leadingText != nil ? 1 : 0.72)
            .help("Play")

            VStack(alignment: .leading, spacing: AppSpacing.tiny) {
                Text(track.title)
                    .fontWeight(appState.isCurrentTrack(track) ? .semibold : .regular)
                if showAlbum {
                    HStack(spacing: AppSpacing.xxs) {
                        ArtistTextLink(name: track.artist, artistID: track.artistID, appState: appState)
                        Text("-")
                        AlbumTextLink(track: track, appState: appState)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            FavoriteButton(track: track, appState: appState)
                .opacity(isHovering || appState.isFavorite(track) ? 1 : AppOpacity.muted)

            TrackMoreMenu(track: track, appState: appState)
                .opacity(isHovering ? 1 : AppOpacity.muted)

            Text(track.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(AppSpacing.row)
        .background(isHovering ? Color.secondary.opacity(AppOpacity.subtle) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

struct TrackMoreMenu: View {
    let track: Track
    @ObservedObject var appState: AppState

    var body: some View {
        Menu {
            Button {
                appState.enqueue(track)
            } label: {
                Label("Add to Queue", systemImage: AppIcon.queue)
            }

            Button {
                appState.startStation(from: track)
            } label: {
                Label("Start Station", systemImage: AppIcon.station)
            }
            .disabled(track.itemID == nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

struct FavoriteButton: View {
    let track: Track
    @ObservedObject var appState: AppState

    var body: some View {
        Button {
            appState.toggleFavorite(track)
        } label: {
            Image(systemName: appState.isFavorite(track) ? AppIcon.favoritesFilled : AppIcon.favorites)
                .foregroundStyle(appState.isFavorite(track) ? Color.red : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(appState.isFavorite(track) ? "Unfavorite" : "Favorite")
    }
}
