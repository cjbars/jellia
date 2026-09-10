import SwiftUI

struct LoginView: View {
    @ObservedObject var appState: AppState
    @State private var showsPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.cozy) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Jellia")
                    .font(.largeTitle.bold())
                Text("Sign in to your Jellyfin server.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.control) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Server URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://jellyfin.example.com", text: $appState.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Username")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Username", text: $appState.username)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .disableAutocorrection(true)
                }

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text("Password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: AppSpacing.xs) {
                        Group {
                            if showsPassword {
                                TextField("Password", text: $appState.password)
                            } else {
                                SecureField("Password", text: $appState.password)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .disableAutocorrection(true)

                        Button {
                            showsPassword.toggle()
                        } label: {
                            Image(systemName: showsPassword ? AppIcon.hidePassword : AppIcon.showPassword)
                        }
                        .buttonStyle(.borderless)
                        .help(showsPassword ? "Hide password" : "Show password")
                    }
                }

                HStack {
                    Button("Sign In") {
                        appState.signIn()
                    }
                    .keyboardShortcut(.defaultAction)

                    Text("Server URL is remembered automatically.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(AppSpacing.panel)
            .frame(width: 440, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))

            if let statusMessage = visibleStatusMessage {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.page)
        .frame(width: 560, height: 520, alignment: .center)
    }

    private var visibleStatusMessage: String? {
        let hiddenMessages = ["Ready", "Signed out"]
        guard !appState.statusMessage.isEmpty, !hiddenMessages.contains(appState.statusMessage) else {
            return nil
        }
        return appState.statusMessage
    }
}

struct MainShellView: View {
    @ObservedObject var appState: AppState
    @State private var sidebarWidth: CGFloat = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sectionSelection) {
                Section("Library") {
                    ForEach([SidebarSection.playlists, .artists, .favorites], id: \.self) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
            }
            .navigationTitle("")
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                sidebarWidth = width
            }
            .searchable(
                text: $appState.searchText,
                placement: .sidebar,
                prompt: "Search music"
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let progress = appState.librarySyncProgress {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        Text(appState.librarySyncMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                }
            }
        } detail: {
            MainColumnView(appState: appState)
                .navigationTitle("")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBarView(appState: appState, progressState: appState.playbackProgress)
                .padding(.leading, playerLeadingInset)
                .padding(.trailing, AppSpacing.lg)
                .padding(.bottom, 12)
        }
        .inspector(isPresented: $appState.isQueueVisible) {
            QueuePanelView(appState: appState)
                .inspectorColumnWidth(
                    min: AppSize.queuePanelWidth,
                    ideal: AppSize.queuePanelWidth,
                    max: AppSize.queuePanelWidth
                )
        }
    }

    private var playerLeadingInset: CGFloat {
        columnVisibility == .detailOnly ? AppSpacing.lg : max(AppSpacing.lg, sidebarWidth + AppSpacing.lg)
    }

    private var sectionSelection: Binding<SidebarSection> {
        Binding(
            get: { appState.selection },
            set: { appState.navigate(to: $0) }
        )
    }
}

private struct MainColumnView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationStack(path: navigationPath) {
            DetailView(appState: appState)
                .navigationTitle("")
                .navigationDestination(for: LibraryRoute.self) { route in
                    DetailView(appState: appState, route: route)
                        .background(.background)
                        .navigationTitle("")
                }
        }
        .navigationTitle("")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var navigationPath: Binding<[LibraryRoute]> {
        Binding(
            get: { appState.navigation.path },
            set: { appState.updateNavigationPath($0) }
        )
    }
}

struct DetailView: View {
    @ObservedObject var appState: AppState
    var route: LibraryRoute?

    var body: some View {
        Group {
            if let route {
                destination(for: route)
            } else {
                rootView
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch appState.selection {
        case .playlists:
            PlaylistTableView(appState: appState)
        case .artists:
            ArtistGridView(appState: appState)
        case .favorites:
            FavoriteTableView(appState: appState)
        }
    }

    @ViewBuilder
    private func destination(for route: LibraryRoute) -> some View {
        Group {
            switch route {
            case .search:
                SearchResultsView(appState: appState)
            case .playlist:
                PlaylistDetailView(appState: appState)
            case .artist:
                ArtistDetailView(appState: appState)
            case .album:
                AlbumDetailView(appState: appState)
            }
        }
    }

}
