import AppKit
import AVFoundation
import Foundation

@MainActor
final class PlaybackController: NSObject {
    private let player = AVPlayer()
    private let nowPlaying = NowPlayingService()
    private var progressTimer: Timer?
    private var itemStatusObservation: NSKeyValueObservation?
    private var currentContext: PlaybackContext?
    private var currentTrack: Track?
    private var lastReportedPosition: TimeInterval = 0
    private var seekGeneration = 0
    private var isSeeking = false
    var onProgress: ((TimeInterval, TimeInterval) -> Void)?
    var onError: ((String) -> Void)?
    var onFinished: (() -> Void)?

    override init() {
        super.init()
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    func configureRemoteCommands(
        play: @escaping @MainActor @Sendable () -> Void,
        pause: @escaping @MainActor @Sendable () -> Void,
        toggle: @escaping @MainActor @Sendable () -> Void,
        next: @escaping @MainActor @Sendable () -> Void,
        previous: @escaping @MainActor @Sendable () -> Void,
        seek: @escaping @MainActor @Sendable (TimeInterval) -> Void,
        setShuffle: @escaping @MainActor @Sendable (Bool) -> Void,
        setRepeat: @escaping @MainActor @Sendable (PlaybackRepeatMode) -> Void,
        like: @escaping @MainActor @Sendable () -> Void,
        dislike: @escaping @MainActor @Sendable () -> Void
    ) {
        nowPlaying.configure(
            play: play,
            pause: pause,
            toggle: toggle,
            next: next,
            previous: previous,
            seek: seek,
            setShuffle: setShuffle,
            setRepeat: setRepeat,
            like: like,
            dislike: dislike
        )
    }

    func updateRemoteState(
        queueIndex: Int,
        queueCount: Int,
        hasTrack: Bool,
        isFavorite: Bool,
        shuffleEnabled: Bool,
        repeatMode: PlaybackRepeatMode,
        canPlayNext: Bool,
        canPlayPrevious: Bool
    ) {
        nowPlaying.updateRemoteState(
            queueIndex: queueIndex,
            queueCount: queueCount,
            hasTrack: hasTrack,
            isFavorite: isFavorite,
            shuffleEnabled: shuffleEnabled,
            repeatMode: repeatMode,
            canPlayNext: canPlayNext,
            canPlayPrevious: canPlayPrevious
        )
    }

    func play(track: Track, session: JellyfinSession, client: any JellyfinAPI) async throws {
        let context = try await client.playbackContext(for: track, session: session)
        try Task.checkCancellation()
        let asset = AVURLAsset(url: context.streamURL, options: [
            "AVURLAssetHTTPHeaderFieldsKey": client.httpHeaders(for: session)
        ])
        let item = AVPlayerItem(asset: asset)
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)
        player.play()
        currentContext = context
        currentTrack = track
        lastReportedPosition = 0
        seekGeneration += 1
        isSeeking = false
        nowPlaying.update(track: track, isPlaying: true, elapsed: 0, duration: context.duration)
        onProgress?(0, context.duration ?? track.duration)
        startProgressTimer(session: session, client: client)
        await client.reportPlaybackStart(track: track, context: context, session: session)
    }

    func toggle(session: JellyfinSession, client: any JellyfinAPI) {
        setPlaying(!isPlaying, session: session, client: client)
    }

    func setPlaying(_ playing: Bool, session: JellyfinSession, client: any JellyfinAPI) {
        guard let track = currentTrack, let context = currentContext else { return }
        if playing {
            player.play()
            nowPlaying.update(track: track, isPlaying: true, elapsed: currentPosition(), duration: context.duration)
            Task { await client.reportPlaybackProgress(track: track, context: context, session: session, position: currentPosition(), isPaused: false) }
        } else {
            player.pause()
            nowPlaying.update(track: track, isPlaying: false, elapsed: currentPosition(), duration: context.duration)
            Task { await client.reportPlaybackProgress(track: track, context: context, session: session, position: currentPosition(), isPaused: true) }
        }
    }

    func stop(session: JellyfinSession, client: any JellyfinAPI) {
        guard let track = currentTrack, let context = currentContext else {
            player.pause()
            nowPlaying.clear()
            return
        }
        let position = currentPosition()
        progressTimer?.invalidate()
        progressTimer = nil
        itemStatusObservation = nil
        seekGeneration += 1
        isSeeking = false
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        player.pause()
        nowPlaying.clear()
        Task { await client.reportPlaybackStopped(track: track, context: context, session: session, position: position) }
        currentContext = nil
        currentTrack = nil
        onProgress?(0, 0)
    }

    func seek(to position: TimeInterval, session: JellyfinSession, client: any JellyfinAPI) {
        guard let track = currentTrack, let context = currentContext else { return }
        let target = CMTime(seconds: position, preferredTimescale: 600)
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        nowPlaying.update(track: track, isPlaying: isPlaying, elapsed: position, duration: context.duration)
        onProgress?(position, context.duration ?? track.duration)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.seekGeneration == generation else { return }
                self.isSeeking = false
                self.lastReportedPosition = position
                self.onProgress?(self.currentPosition(), context.duration ?? track.duration)
                self.reportProgressIfNeeded(session: session, client: client)
            }
        }
    }

    func reportProgressIfNeeded(session: JellyfinSession, client: any JellyfinAPI) {
        guard let track = currentTrack, let context = currentContext else { return }
        Task {
            await client.reportPlaybackProgress(
                track: track,
                context: context,
                session: session,
                position: currentPosition(),
                isPaused: !isPlaying
            )
        }
    }

    func loadNowPlayingArtwork(from url: URL, for track: Track) async {
        let image = await Task.detached(priority: .userInitiated) {
            autoreleasepool { NSImage(contentsOf: url) }
        }.value
        guard let image, currentTrack?.matches(track) == true else { return }
        nowPlaying.setArtwork(image, for: track)
    }

    private func currentPosition() -> TimeInterval {
        PlaybackTime.normalizedPosition(player.currentTime().seconds)
    }

    private func startProgressTimer(session: JellyfinSession, client: any JellyfinAPI) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let position = self.currentPosition()
                let duration = self.currentContext?.duration ?? self.currentTrack?.duration ?? 0
                guard !self.isSeeking else { return }
                self.onProgress?(position, duration)
                guard self.isPlaying, abs(position - self.lastReportedPosition) >= 15 else { return }
                self.lastReportedPosition = position
                self.reportProgressIfNeeded(session: session, client: client)
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Playback failed"
            Task { @MainActor in
                self?.onError?(message)
            }
        }
    }

    @objc private func itemDidPlayToEnd(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem, item === player.currentItem else { return }
        progressTimer?.invalidate()
        progressTimer = nil
        onFinished?()
    }
}
