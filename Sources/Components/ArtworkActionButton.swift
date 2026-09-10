import SwiftUI

struct ArtworkActionButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(AppOpacity.muted))
        .help(help)
    }
}
