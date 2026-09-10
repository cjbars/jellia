import SwiftUI

struct ArtistGridView: View {
    @ObservedObject var appState: AppState
    private let cardWidth: CGFloat = 224
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 224, maximum: 224), spacing: AppSpacing.lg)]

    var body: some View {
        let sections = artistSections
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text(section.title)
                                .font(.title2.bold())
                                .foregroundStyle(.secondary)
                                .id(section.id)

                            LazyVGrid(columns: columns, spacing: AppSpacing.lg) {
                                ForEach(section.artists) { artist in
                                    ArtistCardView(
                                        artist: artist,
                                        width: cardWidth,
                                        artworkURL: { await appState.artworkURL(for: artist, maxWidth: 512) },
                                        onOpen: { appState.openArtist(artist) },
                                        onPlay: { appState.playArtist(artist) },
                                        onStartStation: { appState.startStation(from: artist) },
                                        onLoadSongCount: { appState.loadArtistSongCountIfNeeded(artist) }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(AppSpacing.lg)
                .padding(.bottom, AppSpacing.playerOverlayInset)
            }
            .scrollContentBackground(.hidden)
            .overlay(alignment: .trailing) {
                ArtistAlphabetIndex(sections: sections) { sectionID in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(sectionID, anchor: .top)
                    }
                }
                .padding(.trailing, AppSpacing.xs)
            }
        }
    }

    private var artistSections: [ArtistSection] {
        let artists = appState.artists.filter { $0.matchesSearch(appState.searchText) }
        let grouped = Dictionary(grouping: artists) { artist in
            ArtistSection.sectionTitle(for: artist.name)
        }
        return grouped.keys.sorted(by: ArtistSection.sortTitles)
            .map { title in
                ArtistSection(title: title, artists: grouped[title] ?? [])
            }
    }
}

private struct ArtistSection: Identifiable {
    let title: String
    let artists: [Artist]

    var id: String { title }

    static func sectionTitle(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let upper = String(first).uppercased()
        let isLatin = upper.range(of: #"^[A-Z]$"#, options: .regularExpression) != nil
        let isCyrillic = upper.range(of: #"^[А-ЯЁ]$"#, options: .regularExpression) != nil
        return isLatin || isCyrillic ? upper : "#"
    }

    static func sortTitles(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == "#" { return false }
        if rhs == "#" { return true }
        return lhs < rhs
    }
}

private struct ArtistAlphabetIndex: View {
    let sections: [ArtistSection]
    let scrollTo: (String) -> Void
    private let latinTitles = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    private let cyrillicTitles = Array("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ").map(String.init)

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xxs) {
            indexColumn(latinTitles + ["#"])
            indexColumn(cyrillicTitles)
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.xxs)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(AppOpacity.faint), radius: 10, y: 4)
    }

    private func indexColumn(_ titles: [String]) -> some View {
        VStack(spacing: AppSpacing.hairline) {
            ForEach(titles, id: \.self) { title in
                indexButton(title)
            }
        }
    }

    private func indexButton(_ title: String) -> some View {
        let isAvailable = sections.contains(where: { $0.id == title })
        return Button(title) {
            scrollTo(title)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(isAvailable ? Color.secondary : Color.secondary.opacity(AppOpacity.disabled))
        .frame(width: 16, height: 13)
        .disabled(!isAvailable)
    }
}

private enum ArtistDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case albums = "Albums"
    case songs = "Songs"
    case appearances = "Appearances"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "sparkles"
        case .albums: return AppIcon.album
        case .songs: return AppIcon.track
        case .appearances: return "person.2"
        }
    }
}

struct ArtistDetailView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: ArtistDetailTab = .overview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.cozy) {
                if appState.isLoadingArtist {
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }

                if let artist = appState.selectedArtist {
                    HStack(alignment: .top, spacing: AppSpacing.hero) {
                        RemoteArtworkView(
                            artworkID: artist.itemID ?? artist.id,
                            fallbackSymbol: AppIcon.artists,
                            fallbackGradient: AppFallback.artist
                        ) {
                            await appState.artworkURL(for: artist)
                        }
                        .frame(width: AppSize.detailArtwork, height: AppSize.detailArtwork)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))

                        VStack(alignment: .leading, spacing: AppSpacing.control) {
                            Text(artist.name)
                                .font(.system(size: 38, weight: .bold))
                                .lineLimit(2)

                            ArtistMetaView(artist: artist)

                            HStack(spacing: AppSpacing.control) {
                                HeaderIconButton(icon: AppIcon.play, help: "Play") {
                                    appState.playSelectedArtist()
                                }
                                .disabled(artist.itemID == nil && appState.selectedArtistTracks.isEmpty)

                                HeaderIconButton(icon: AppIcon.station, help: "Start Station") {
                                    appState.startStation(from: artist)
                                }
                                .disabled(artist.itemID == nil)
                            }
                            .padding(.top, AppSpacing.xxs)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                }

                ArtistDetailTabs(selectedTab: $selectedTab)

                Group {
                    if appState.isLoadingArtist {
                        LoadingRowsView()
                    } else if let error = appState.artistLoadError {
                        LoadErrorView(message: error) {
                            appState.retryArtistLoad()
                        }
                    } else {
                        switch selectedTab {
                        case .overview:
                            ArtistOverviewView(appState: appState)
                        case .albums:
                            ArtistAlbumsView(appState: appState, albums: appState.selectedArtistAlbums)
                        case .songs:
                            ArtistSongsView(appState: appState)
                        case .appearances:
                            ArtistTrackListView(
                                appState: appState,
                                tracks: appState.selectedArtistAppearances,
                                emptyText: "No appearances for this artist."
                            )
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, AppSpacing.playerOverlayInset)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct ArtistMetaView: View {
    let artist: Artist

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if !artist.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(artist.genre, systemImage: "tag")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ArtistDetailTabs: View {
    @Binding var selectedTab: ArtistDetailTab

    var body: some View {
        HStack(spacing: AppSpacing.panel) {
            ForEach(ArtistDetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: AppSpacing.compact) {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .labelStyle(.titleAndIcon)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
            }
        }
        .font(.body)
        .padding(.top, AppSpacing.xxs)
    }
}

private struct ArtistOverviewView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let topTracks = Array(appState.selectedArtistTracks.prefix(5))
        let topAlbums = Array(appState.selectedArtistAlbums.prefix(8))
        let topAppearances = Array(appState.selectedArtistAppearances.prefix(5))
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if !topTracks.isEmpty {
                Text("Top Tracks")
                    .font(.headline)
                VStack(spacing: AppSpacing.xs) {
                    ForEach(topTracks) { track in
                        TrackRow(track: track, appState: appState)
                    }
                }
            }

            if !topAlbums.isEmpty {
                Text("Albums")
                    .font(.headline)
                ArtistAlbumsView(appState: appState, albums: topAlbums)
            }

            if !topAppearances.isEmpty {
                Text("Appearances")
                    .font(.headline)
                ArtistTrackListView(
                    appState: appState,
                    tracks: topAppearances,
                    emptyText: ""
                )
            }

            if topTracks.isEmpty && topAlbums.isEmpty && topAppearances.isEmpty && !appState.isLoadingArtist {
                Text("No content for this artist.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ArtistAlbumsView: View {
    @ObservedObject var appState: AppState
    let albums: [Album]

    var body: some View {
        if albums.isEmpty && !appState.isLoadingArtist {
            Text("No albums for this artist.")
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppSpacing.sm)], spacing: AppSpacing.sm) {
                ForEach(albums) { album in
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
    }
}

private struct ArtistSongsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ArtistTrackListView(
            appState: appState,
            tracks: appState.selectedArtistTracks,
            emptyText: "No tracks for this artist."
        )
        .task(id: appState.selectedArtistAlbums) {
            appState.loadSelectedArtistTracksFromAlbumsIfNeeded()
        }
    }
}

private struct ArtistTrackListView: View {
    @ObservedObject var appState: AppState
    let tracks: [Track]
    let emptyText: String

    var body: some View {
        if tracks.isEmpty && !appState.isLoadingArtist {
            if !emptyText.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: AppSpacing.xxs) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
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
}
