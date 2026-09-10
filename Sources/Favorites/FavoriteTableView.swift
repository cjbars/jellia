import SwiftUI

struct FavoriteTableView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let favorites = appState.favoriteTracks.filter { $0.matchesSearch(appState.searchText) }

        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                favoritesHeader(favorites)

                if favorites.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: AppSpacing.xxs) {
                        ForEach(Array(favorites.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                appState: appState,
                                showAlbum: true,
                                showArtwork: true,
                                leadingText: String(index + 1)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.playerOverlayInset)
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    private func favoritesHeader(_ favorites: [Track]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text("Favorites")
                    .font(.system(size: 38, weight: .bold))

                HeaderIconButton(icon: AppIcon.play, help: "Play") {
                    appState.playFavorites(favorites)
                }
                .disabled(favorites.isEmpty)
            }

            Label("\(favorites.count) tracks", systemImage: AppIcon.favoritesFilled)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: AppIcon.favorites)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No Favorite Tracks")
                .font(.title3.bold())

            Text("Tracks you mark as favorites will appear here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }
}
