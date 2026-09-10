import AppKit
import SwiftUI
import UserNotifications

extension Notification.Name {
    static let resizeMainWindow = Notification.Name("jellia.resizeMainWindow")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var windowItem: NSMenuItem?
    private var playPauseItem: NSMenuItem?
    private var nextItem: NSMenuItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if activateExistingInstanceIfNeeded() {
            NSApplication.shared.terminate(nil)
            return
        }
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "Jellia", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        if let window = NSApplication.shared.windows.first {
            window.delegate = self
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resizeMainWindow(_:)),
            name: .resizeMainWindow,
            object: nil
        )
        setupMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopPlayback()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow(sender)
        return false
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentProcessID })
        else {
            return false
        }
        existing.activate(options: [.activateAllWindows])
        return true
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = makeStatusItemIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "Jellia"
        }

        let menu = NSMenu()
        menu.delegate = self

        let connectionStatusItem = NSMenuItem(title: "Jellia", action: nil, keyEquivalent: "")
        connectionStatusItem.isEnabled = false
        menu.addItem(connectionStatusItem)

        menu.addItem(.separator())

        let windowItem = NSMenuItem(title: "Show Window", action: #selector(toggleWindow), keyEquivalent: "")
        windowItem.target = self
        menu.addItem(windowItem)
        self.windowItem = windowItem

        menu.addItem(.separator())

        let playPauseItem = NSMenuItem(title: "Play", action: #selector(togglePlaybackFromMenu), keyEquivalent: "")
        playPauseItem.target = self
        menu.addItem(playPauseItem)
        self.playPauseItem = playPauseItem

        let nextItem = NSMenuItem(title: "Next", action: #selector(nextFromMenu), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)
        self.nextItem = nextItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func makeStatusItemIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.65
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: 1, y: 8.4))
            path.curve(
                to: NSPoint(x: 7.2, y: 7.6),
                controlPoint1: NSPoint(x: 3.2, y: 11.2),
                controlPoint2: NSPoint(x: 5.2, y: 4.8)
            )
            path.curve(
                to: NSPoint(x: 8.2, y: 13.2),
                controlPoint1: NSPoint(x: 8.4, y: 9.1),
                controlPoint2: NSPoint(x: 7.7, y: 11.4)
            )
            path.curve(
                to: NSPoint(x: 12.1, y: 13.1),
                controlPoint1: NSPoint(x: 8.6, y: 15.7),
                controlPoint2: NSPoint(x: 11.8, y: 15.6)
            )
            path.curve(
                to: NSPoint(x: 9.2, y: 7.1),
                controlPoint1: NSPoint(x: 12.3, y: 10.8),
                controlPoint2: NSPoint(x: 9.6, y: 10.2)
            )
            path.curve(
                to: NSPoint(x: 12.4, y: 7.2),
                controlPoint1: NSPoint(x: 8.9, y: 4.9),
                controlPoint2: NSPoint(x: 11, y: 4.8)
            )
            path.curve(
                to: NSPoint(x: 17, y: 8.1),
                controlPoint1: NSPoint(x: 14.2, y: 10.2),
                controlPoint2: NSPoint(x: 15.8, y: 9.3)
            )
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Jellia"
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        let state = AppState.shared
        windowItem?.title = NSApplication.shared.windows.first?.isVisible == true ? "Hide Window" : "Show Window"
        playPauseItem?.title = state.isPlaying ? "Pause" : "Play"
        playPauseItem?.isEnabled = state.canPlayOrPause
        nextItem?.isEnabled = state.canPlayNext
    }

    @objc private func togglePlaybackFromMenu() {
        AppState.shared.togglePlayback()
    }

    @objc private func nextFromMenu() {
        AppState.shared.playNextTrack()
    }

    @objc private func toggleWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        if window.isVisible {
            hideWindow(window)
        } else {
            showWindow()
        }
    }

    private func hideWindow(_ window: NSWindow) {
        window.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func showWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func resizeMainWindow(_ notification: Notification) {
        guard let window = NSApplication.shared.windows.first,
              let size = notification.object as? NSSize
        else {
            return
        }

        let currentFrame = window.frame
        let nextOrigin = NSPoint(
            x: currentFrame.midX - size.width / 2,
            y: currentFrame.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: nextOrigin, size: size), display: true, animate: true)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@main
struct JelliaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Window("Jellia", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: AppSize.mainWindow.width, height: AppSize.mainWindow.height)
        Settings {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 520, height: 420)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Library") {
                Button("Refresh Library") {
                    appState.refreshLibrary()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!appState.signedIn)

                Button("Clear Artwork Cache") {
                    appState.clearCache()
                }
                .disabled(!appState.signedIn)

                Divider()

                Button("Sign Out") {
                    appState.signOut()
                }
                .disabled(!appState.signedIn)
            }
        }
    }
}
