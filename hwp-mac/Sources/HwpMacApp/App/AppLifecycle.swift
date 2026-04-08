import AppKit
import SwiftUI

@MainActor
final class HwpMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        EditorShortcutCoordinator.shared.installIfNeeded()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            AppWindowCoordinator.shared.activateCurrentWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindowCoordinator.shared.activateCurrentWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppWindowCoordinator.shared.activateCurrentWindow()
    }
}

@MainActor
final class EditorShortcutCoordinator {
    static let shared = EditorShortcutCoordinator()

    weak var documentController: DocumentController?
    private var monitor: Any?

    private init() {}

    func register(documentController: DocumentController) {
        self.documentController = documentController
        installIfNeeded()
    }

    func installIfNeeded() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard
            let documentController,
            let window = NSApp.keyWindow,
            window.isKeyWindow,
            shouldRouteShortcut(in: window)
        else {
            return event
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command) else { return event }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            documentController.commandBus.selectAll()
            return nil
        case "c":
            documentController.commandBus.copy()
            return nil
        case "x":
            documentController.commandBus.cut()
            return nil
        case "v":
            documentController.commandBus.paste()
            return nil
        case "z":
            if modifiers.contains(.shift) {
                documentController.commandBus.redo()
            } else {
                documentController.commandBus.undo()
            }
            return nil
        default:
            return event
        }
    }

    private func shouldRouteShortcut(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return true }

        if responder is NSTextView {
            return false
        }

        return true
    }
}

@MainActor
final class AppWindowCoordinator {
    static let shared = AppWindowCoordinator()

    weak var mainWindow: NSWindow?

    private init() {}

    func register(window: NSWindow) {
        mainWindow = window
        configure(window)

        DispatchQueue.main.async {
            self.activate(window: window)
        }
    }

    func activateCurrentWindow() {
        guard let mainWindow else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        activate(window: mainWindow)
    }

    private func configure(_ window: NSWindow) {
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .unifiedCompact
        }
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isMovableByWindowBackground = false
    }

    private func activate(window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindowIfNeeded()
    }
}

final class WindowObserverView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override var intrinsicContentSize: NSSize {
        .zero
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfNeeded()
    }

    func resolveWindowIfNeeded() {
        guard let window else { return }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.onResolve?(window)
        }
    }
}
