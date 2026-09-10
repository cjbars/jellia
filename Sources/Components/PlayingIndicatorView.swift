import SwiftUI

struct PlayingIndicatorView: View {
    let isPlaying: Bool

    var body: some View {
        Group {
            if isPlaying {
                TimelineView(.animation) { timeline in
                    bars(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(at: 0)
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel("Playing")
    }

    private func bars(at time: TimeInterval) -> some View {
        let signals = [
            (frequency: 4.7, phase: 0.2),
            (frequency: 6.1, phase: 2.0),
            (frequency: 5.3, phase: 4.1),
            (frequency: 7.0, phase: 5.4)
        ]
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(signals.enumerated()), id: \.offset) { _, signal in
                let level = (sin(time * signal.frequency + signal.phase) + 1) / 2
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 3 + CGFloat(level) * 10)
            }
        }
        .frame(height: 14, alignment: .bottom)
    }
}
