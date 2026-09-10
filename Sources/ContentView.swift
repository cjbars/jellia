import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        Group {
            if appState.signedIn {
                MainShellView(appState: appState)
            } else {
                LoginView(appState: appState)
            }
        }
        .task {
            resizeMainWindow(signedIn: appState.signedIn)
        }
        .onChange(of: appState.signedIn) { _, signedIn in
            resizeMainWindow(signedIn: signedIn)
        }
    }

    private func resizeMainWindow(signedIn: Bool) {
        let configuredSize = signedIn ? AppSize.mainWindow : AppSize.loginWindow
        let size = NSSize(width: configuredSize.width, height: configuredSize.height)
        NotificationCenter.default.post(name: .resizeMainWindow, object: size)
    }
}
