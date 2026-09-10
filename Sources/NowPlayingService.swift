import AppKit
import Foundation
import MediaPlayer

@MainActor
final class NowPlayingService {
    private var isConfigured = false
    private var currentTrackKey: String?
    private var artwork: MPMediaItemArtwork?
    private var queueIndex = 0
    private var queueCount = 0

    func configure(
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
        guard !isConfigured else { return }
        isConfigured = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in
            Self.perform(play)
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Self.perform(pause)
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Self.perform(toggle)
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Self.perform(next)
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Self.perform(previous)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Self.perform { seek(position) }
            return .success
        }
        center.changeShuffleModeCommand.addTarget { event in
            guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            switch event.shuffleType {
            case .off:
                Self.perform { setShuffle(false) }
            case .items, .collections:
                Self.perform { setShuffle(true) }
            @unknown default:
                return .commandFailed
            }
            return .success
        }
        center.changeRepeatModeCommand.addTarget { event in
            guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            switch event.repeatType {
            case .off:
                Self.perform { setRepeat(.off) }
            case .all:
                Self.perform { setRepeat(.all) }
            case .one:
                Self.perform { setRepeat(.one) }
            @unknown default:
                return .commandFailed
            }
            return .success
        }
        center.likeCommand.localizedTitle = "Add to Favorites"
        center.likeCommand.localizedShortTitle = "Favorite"
        center.likeCommand.addTarget { _ in
            Self.perform(like)
            return .success
        }
        center.dislikeCommand.localizedTitle = "Remove from Favorites"
        center.dislikeCommand.localizedShortTitle = "Unfavorite"
        center.dislikeCommand.addTarget { _ in
            Self.perform(dislike)
            return .success
        }
    }

    private nonisolated static func perform(_ action: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in action() }
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
        self.queueIndex = queueIndex
        self.queueCount = queueCount
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = hasTrack
        center.pauseCommand.isEnabled = hasTrack
        center.togglePlayPauseCommand.isEnabled = hasTrack
        center.nextTrackCommand.isEnabled = hasTrack && canPlayNext
        center.previousTrackCommand.isEnabled = hasTrack && canPlayPrevious
        center.changePlaybackPositionCommand.isEnabled = hasTrack
        center.changeShuffleModeCommand.isEnabled = queueCount > 1
        center.changeShuffleModeCommand.currentShuffleType = shuffleEnabled ? .items : .off
        center.changeRepeatModeCommand.isEnabled = hasTrack
        center.changeRepeatModeCommand.currentRepeatType = switch repeatMode {
        case .off: .off
        case .all: .all
        case .one: .one
        }
        center.likeCommand.isEnabled = hasTrack && !isFavorite
        center.likeCommand.isActive = isFavorite
        center.dislikeCommand.isEnabled = hasTrack && isFavorite
        center.dislikeCommand.isActive = !isFavorite

        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        appendQueueInfo(to: &info)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func update(track: Track, isPlaying: Bool, elapsed: TimeInterval, duration: TimeInterval?) {
        let trackKey = track.itemID ?? track.id
        if currentTrackKey != trackKey {
            currentTrackKey = trackKey
            artwork = nil
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        appendQueueInfo(to: &info)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func appendQueueInfo(to info: inout [String: Any]) {
        if queueCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = min(max(queueIndex, 0), queueCount - 1)
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
        } else {
            info.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackQueueIndex)
            info.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackQueueCount)
        }
    }

    func setArtwork(_ image: NSImage, for track: Track) {
        let trackKey = track.itemID ?? track.id
        guard currentTrackKey == trackKey else { return }

        let artwork = Self.makeArtwork(from: image)
        self.artwork = artwork

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private nonisolated static func makeArtwork(from image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func clear() {
        currentTrackKey = nil
        artwork = nil
        queueIndex = 0
        queueCount = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
