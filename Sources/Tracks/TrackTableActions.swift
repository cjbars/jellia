import SwiftUI

struct TrackTableActions: View {
    let track: Track
    @ObservedObject var appState: AppState
    var showsPlay = true

    var body: some View {
        HStack {
            if showsPlay {
                Button("Play") { appState.play(track) }
                    .buttonStyle(.borderless)
            }
            Button("Queue") { appState.enqueue(track) }
                .buttonStyle(.borderless)
            FavoriteButton(track: track, appState: appState)
            Button("Station") { appState.startStation(from: track) }
                .buttonStyle(.borderless)
                .disabled(track.itemID == nil)
        }
    }
}
