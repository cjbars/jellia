import SwiftUI

enum AppRadius {
    static let small: CGFloat = 8
    static let large: CGFloat = 14
}

enum AppSize {
    static let navigationControl: CGFloat = 38
    static let queuePanelWidth: CGFloat = 320
    static let detailArtwork: CGFloat = 220
    static let playerControlsWidth: CGFloat = 150
    static let playerTrackMinimumWidth: CGFloat = 260
    static let playerArtworkSize: CGFloat = 34
    static let playerHeight: CGFloat = 54
    static let mainWindow = CGSize(width: 1100, height: 760)
    static let loginWindow = CGSize(width: 560, height: 520)
}

enum AppSpacing {
    static let hairline: CGFloat = 1
    static let tiny: CGFloat = 2
    static let xxs: CGFloat = 4
    static let compact: CGFloat = 6
    static let xs: CGFloat = 8
    static let row: CGFloat = 10
    static let sm: CGFloat = 12
    static let control: CGFloat = 14
    static let md: CGFloat = 16
    static let panel: CGFloat = 18
    static let cozy: CGFloat = 22
    static let lg: CGFloat = 24
    static let hero: CGFloat = 26
    static let page: CGFloat = 28
    static let xl: CGFloat = 32
    static let playerOverlayInset: CGFloat = 96
}

enum AppOpacity {
    static let hidden: Double = 0
    static let faint: Double = 0.08
    static let subtle: Double = 0.12
    static let soft: Double = 0.16
    static let disabled: Double = 0.28
    static let muted: Double = 0.45
    static let strong: Double = 0.9
}

enum AppFallback {
    static let artist = [Color.cyan.opacity(AppOpacity.soft), Color.blue.opacity(AppOpacity.faint)]
    static let album = [Color.cyan.opacity(AppOpacity.disabled), Color.blue.opacity(AppOpacity.soft)]
    static let playlist = [Color.blue.opacity(AppOpacity.disabled), Color.cyan.opacity(AppOpacity.soft)]
    static let track = [Color.cyan.opacity(AppOpacity.disabled), Color.blue.opacity(AppOpacity.soft)]
}
