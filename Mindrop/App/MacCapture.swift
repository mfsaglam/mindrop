#if os(macOS)
import AppKit
import MindropCore
import SwiftUI

/// Owns the editor window even when the library and Settings windows are closed.
@MainActor
final class MacCapture: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(repository: MemoryRepository, details: String = "") {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 528),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "New Memory")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView:
            MemoryEditorView(mode: .create, repository: repository, initialDetails: details) { [weak window] in
                window?.close()
            }
            .padding(.top, 18)
        )
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
#endif
