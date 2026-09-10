import AppKit
import SwiftUI

struct LibrarySearchField: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NativeSearchField(text: $appState.searchText) {
            appState.clearSearch()
        }
        .padding(.horizontal, AppSpacing.sm)
        .frame(height: AppSize.navigationControl)
        .glassEffect(.regular, in: Capsule())
    }
}

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let onClear: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SearchInputView {
        let input = SearchInputView()
        input.textField.delegate = context.coordinator
        input.clearButton.target = context.coordinator
        input.clearButton.action = #selector(Coordinator.cancelSearch(_:))
        input.onClearRequested = { [weak coordinator = context.coordinator] in
            coordinator?.cancelSearch(nil)
        }
        context.coordinator.input = input
        return input
    }

    func updateNSView(_ input: SearchInputView, context: Context) {
        context.coordinator.parent = self
        input.setText(text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSearchField
        weak var input: SearchInputView?

        init(parent: NativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let value = textField.stringValue
            input?.updateClearButton(for: value)
            if parent.text != value {
                parent.text = value
            }
            if value.isEmpty {
                parent.onClear()
            }
        }

        @objc func cancelSearch(_ sender: Any?) {
            input?.setText("")
            if !parent.text.isEmpty {
                parent.text = ""
            }
            parent.onClear()
        }
    }
}

@MainActor
private final class SearchInputView: NSView {
    let textField = ClickThroughTextField()
    let clearButton = NSButton()
    private let searchIcon = NSImageView()
    var onClearRequested: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setText(_ value: String) {
        if textField.stringValue != value {
            textField.stringValue = value
        }
        updateClearButton(for: value)
    }

    func updateClearButton(for value: String) {
        clearButton.isHidden = value.isEmpty
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !clearButton.isHidden, clearButton.frame.insetBy(dx: -6, dy: -6).contains(point) {
            onClearRequested?()
            return
        }
        textField.activate()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func configure() {
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        searchIcon.contentTintColor = .secondaryLabelColor
        searchIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        textField.placeholderString = "Search music"
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingTail

        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear search")
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.refusesFirstResponder = true
        clearButton.toolTip = "Clear search"
        clearButton.isHidden = true

        [searchIcon, textField, clearButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 24),
            searchIcon.heightAnchor.constraint(equalToConstant: 24),

            textField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: AppSpacing.xs),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),

            clearButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: AppSpacing.xs),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 32),
            clearButton.heightAnchor.constraint(equalToConstant: AppSize.navigationControl)
        ])
    }
}

@MainActor
private final class ClickThroughTextField: NSTextField {
    private var allowsFocus = false

    override var acceptsFirstResponder: Bool {
        allowsFocus
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func activate() {
        allowsFocus = true
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        activate()
        super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            allowsFocus = false
        }
        return didResign
    }
}
