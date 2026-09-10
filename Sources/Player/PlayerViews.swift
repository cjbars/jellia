import SwiftUI
import UniformTypeIdentifiers

struct QueuePanelView: View {
    @ObservedObject var appState: AppState
    @State private var draggedQueueIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("\(appState.queue.count) tracks")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appState.shuffleQueue()
                } label: {
                    Image(systemName: AppIcon.shuffle)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(appState.queue.count < 2)
                .help("Shuffle queue")

                Button {
                    appState.clearQueue()
                } label: {
                    Image(systemName: AppIcon.remove)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(appState.queue.isEmpty && !appState.isPlaying)
                .help("Clear queue")
            }

            if appState.queue.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcon.queue)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("Queue is empty")
                        .font(.headline)
                    Text("Add tracks to start listening.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                    ForEach(Array(appState.queue.enumerated()), id: \.offset) { index, track in
                        QueueTrackRow(
                            track: track,
                            index: index,
                            appState: appState,
                            draggedQueueIndex: $draggedQueueIndex
                        )
                    }
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.panel)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                .allowsHitTesting(false)
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}

private struct QueueTrackRow: View {
    let track: Track
    let index: Int
    @ObservedObject var appState: AppState
    @Binding var draggedQueueIndex: Int?

    @State private var isHovering = false
    @State private var isDropTarget = false

    var body: some View {
        let isCurrentTrack = PlaybackQueueState.currentIndex(in: appState.queue, for: appState.currentTrack) == index

        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14, height: AppSize.navigationControl)
                .opacity(isHovering ? 1 : 0)
                .help("Drag to reorder")

            RemoteArtworkView(
                artworkID: track.itemID ?? track.id,
                fallbackSymbol: AppIcon.track,
                fallbackGradient: AppFallback.track,
                size: 34,
                maxPixelSize: 128
            ) {
                await appState.artworkURL(for: track, maxWidth: 128)
            }
            .frame(width: AppSize.navigationControl, height: AppSize.navigationControl)

                VStack(alignment: .leading, spacing: AppSpacing.tiny) {
                    HStack(spacing: AppSpacing.xs) {
                    if isCurrentTrack && appState.isPlaying {
                        PlayingIndicatorView(isPlaying: true)
                    }
                    Text(track.title)
                        .fontWeight(isCurrentTrack ? .semibold : .regular)
                        .lineLimit(2)
                }

                ArtistTextLink(name: track.artist, artistID: track.artistID, appState: appState)
                    .font(.caption)
            }

            Spacer()

            HStack(spacing: AppSpacing.tiny) {
                Text(track.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)

                Button {
                    appState.removeQueueItem(at: index)
                } label: {
                    Image(systemName: AppIcon.remove)
                        .frame(width: 20, height: 24)
                }
                .opacity(isHovering ? 1 : AppOpacity.hidden)
                .help("Remove")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppSpacing.tiny)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .overlay(alignment: .top) {
            if isDropTarget {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, AppSpacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onDrag {
            draggedQueueIndex = index
            return NSItemProvider(object: "jellia.queue" as NSString)
        } preview: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: AppIcon.track)
                    .foregroundStyle(Color.accentColor)
                Text(track.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .glassEffect(.regular, in: Capsule())
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: QueueRowDropDelegate(
                destinationIndex: index,
                draggedQueueIndex: $draggedQueueIndex,
                isTargeted: $isDropTarget,
                appState: appState
            )
        )
        .onTapGesture(count: 2) {
            appState.play(track)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct QueueRowDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var draggedQueueIndex: Int?
    @Binding var isTargeted: Bool
    let appState: AppState

    func validateDrop(info: DropInfo) -> Bool {
        draggedQueueIndex != nil
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            isTargeted = false
            draggedQueueIndex = nil
        }
        guard let sourceIndex = draggedQueueIndex else { return false }
        appState.moveQueueItem(from: sourceIndex, to: destinationIndex)
        return true
    }
}

struct PlayerBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var progressState: PlaybackProgressState
    @State private var pendingSeekPosition: TimeInterval?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xs) {
                PlayerIconButton(
                    icon: AppIcon.shuffle,
                    size: 13,
                    disabled: false,
                    isActive: appState.isShuffleEnabled
                ) {
                    appState.toggleShuffle()
                }

                PlayerIconButton(
                    icon: AppIcon.previous,
                    size: 17,
                    disabled: !appState.canPlayPrevious
                ) {
                    appState.playPreviousTrack()
                }

                PlayerIconButton(
                    icon: appState.isPlaying ? AppIcon.pause : AppIcon.play,
                    size: 28,
                    disabled: !appState.canPlayOrPause
                ) {
                    appState.togglePlayback()
                }

                PlayerIconButton(
                    icon: AppIcon.next,
                    size: 17,
                    disabled: !appState.canPlayNext
                ) {
                    appState.playNextTrack()
                }
            }
            .frame(width: AppSize.playerControlsWidth, alignment: .leading)

            HStack(spacing: AppSpacing.sm) {
                RemoteArtworkView(
                    artworkID: appState.currentTrack.itemID ?? appState.currentTrack.id,
                    fallbackSymbol: AppIcon.track,
                    fallbackGradient: AppFallback.track,
                    size: AppSize.playerArtworkSize,
                    maxPixelSize: 128
                ) {
                    await appState.artworkURL(for: appState.currentTrack, maxWidth: 128)
                }
                .frame(width: AppSize.playerArtworkSize, height: AppSize.playerArtworkSize)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                        Text(appState.currentTrack.title)
                            .font(.headline)
                            .lineLimit(1)
                        ArtistTextLink(
                            name: appState.currentTrack.artist,
                            artistID: appState.currentTrack.artistID,
                            appState: appState
                        )
                    }

                    TrackProgressView(
                        position: pendingSeekPosition ?? progressState.position,
                        duration: progressState.duration,
                        progress: progressRatio,
                        isEnabled: progressState.duration > 0
                    ) { ratio in
                        pendingSeekPosition = ratio * progressState.duration
                    } seek: { ratio in
                        let position = ratio * progressState.duration
                        pendingSeekPosition = position
                        appState.seek(to: position)
                        pendingSeekPosition = nil
                    }
                }
                .frame(minWidth: AppSize.playerTrackMinimumWidth, maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                minWidth: AppSize.playerTrackMinimumWidth,
                maxWidth: .infinity,
                alignment: .leading
            )

            PlayerIconButton(
                icon: AppIcon.queue,
                size: 18,
                disabled: false,
                isActive: appState.isQueueVisible
            ) {
                appState.toggleQueueVisibility()
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: AppSize.playerHeight, maxHeight: AppSize.playerHeight, alignment: .leading)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(AppOpacity.soft), radius: 22, y: 10)
    }

    private var progressRatio: Double {
        let position = pendingSeekPosition ?? progressState.position
        guard progressState.duration > 0 else { return 0 }
        return min(max(position / progressState.duration, 0), 1)
    }
}

private struct TrackProgressView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let progress: Double
    let isEnabled: Bool
    let previewSeek: (Double) -> Void
    let seek: (Double) -> Void

    @State private var isHovering = false
    @State private var showsTimes = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var sliderValue = 0.0
    @State private var isEditingSlider = false

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            if showsTimes {
                HStack {
                    Text(timeText(position))
                    Spacer()
                    Text("-\(timeText(max(duration - position, 0)))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .transition(.opacity)
            }

            Slider(value: $sliderValue, in: 0...1, onEditingChanged: { editing in
                isEditingSlider = editing
                if !editing {
                    seek(sliderValue)
                }
            })
            .tint(.accentColor)
            .controlSize(.mini)
            .disabled(!isEnabled)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(timeText(position)) of \(timeText(duration))")
        }
        .animation(.easeInOut(duration: 0.16), value: showsTimes)
        .onAppear {
            sliderValue = progress
        }
        .onChange(of: progress) { _, newValue in
            guard !isEditingSlider else { return }
            sliderValue = newValue
        }
        .onChange(of: sliderValue) { _, newValue in
            guard isEditingSlider else { return }
            previewSeek(newValue)
        }
        .onHover { hovering in
            isHovering = hovering
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if isHovering {
                            showsTimes = true
                        }
                    }
                }
            } else {
                showsTimes = false
            }
        }
    }

    private func timeText(_ value: TimeInterval) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let totalSeconds = Int(value.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct PlayerIconButton: View {
    let icon: String
    let size: CGFloat
    var disabled: Bool
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(disabled ? AppOpacity.muted : AppOpacity.strong))
        .disabled(disabled)
    }
}
