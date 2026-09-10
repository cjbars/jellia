import SwiftUI

struct ArtistCardView: View {
    let artist: Artist
    let width: CGFloat
    let artworkURL: () async -> URL?
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onStartStation: () -> Void
    let onLoadSongCount: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ZStack(alignment: .bottomLeading) {
                RemoteArtworkView(
                    artworkID: artist.itemID ?? artist.id,
                    fallbackSymbol: AppIcon.artists,
                    fallbackGradient: AppFallback.artist,
                    maxPixelSize: 512
                ) {
                    await artworkURL()
                }
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                if isHovering {
                    HStack(spacing: AppSpacing.xs) {
                        ArtworkActionButton(icon: AppIcon.play, help: "Play") {
                            onPlay()
                        }

                        ArtworkActionButton(icon: AppIcon.station, help: "Start Station") {
                            onStartStation()
                        }
                        .disabled(artist.itemID == nil)
                    }
                    .padding(AppSpacing.xs)
                    .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(artist.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(artist.songCount >= 0 ? "\(artist.songCount) songs" : "… songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(width: width, alignment: .topLeading)
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.012 : 1)
        .shadow(color: .black.opacity(isHovering ? 0.10 : 0), radius: isHovering ? 12 : 0, y: 5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onOpen()
        }
        .onAppear(perform: onLoadSongCount)
    }
}
