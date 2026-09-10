import SwiftUI

struct ArtistTextLink: View {
    let name: String
    var artistID: String? = nil
    @ObservedObject var appState: AppState
    var lineLimit = 1

    var body: some View {
        LibraryEntityTextLink(title: name, help: "Open artist", lineLimit: lineLimit) {
            appState.openArtist(id: artistID, named: name)
        }
    }
}

struct AlbumTextLink: View {
    let track: Track
    @ObservedObject var appState: AppState
    var lineLimit = 1

    var body: some View {
        LibraryEntityTextLink(title: track.album, help: "Open album", lineLimit: lineLimit) {
            appState.openAlbum(from: track)
        }
    }
}

private struct LibraryEntityTextLink: View {
    let title: String
    let help: String
    let lineLimit: Int
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(lineLimit)
                .underline(isHovering)
                .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}
