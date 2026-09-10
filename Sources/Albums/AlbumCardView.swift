import SwiftUI

struct AlbumCardView: View {
    let album: Album
    let dateFormat: DateDisplayFormat
    let artworkURL: () async -> URL?
    let onOpen: () -> Void
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ZStack(alignment: .bottomLeading) {
                RemoteArtworkView(
                    artworkID: album.itemID ?? album.id,
                    fallbackSymbol: AppIcon.album,
                    fallbackGradient: AppFallback.album,
                    maxPixelSize: 512
                ) {
                    await artworkURL()
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                if isHovering {
                    ArtworkActionButton(icon: AppIcon.play, help: "Play") {
                        onPlay()
                    }
                    .padding(AppSpacing.xs)
                    .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(album.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: AppSpacing.xxs) {
                    if let releaseText = album.releaseText(format: dateFormat) {
                        Text(releaseText)
                        Text("·")
                    }
                    Text("\(album.trackCount) tracks")
                }
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
            onOpen()
        }
    }
}
