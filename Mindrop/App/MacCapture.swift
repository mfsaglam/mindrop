#if os(macOS)
import AppKit
import MindropCore
import StoreKit
import SwiftUI

/// Keeps independent drafts open even when the library and Settings windows are closed.
@MainActor
final class MacCapture: NSObject, NSWindowDelegate {
    private var windows: [NSWindow] = []

    func show(repository: MemoryRepository, details: String, folderID: UUID) {
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
            MemoryEditorView(
                mode: .create, repository: repository, initialDetails: details, folderID: folderID,
                onCreate: { [weak self] in self?.memoryDidCreate() },
                onClose: { [weak window] in window?.close() }
            )
            .padding(.top, 18)
        )
        if let previousWindow = windows.last {
            let topLeft = NSPoint(x: previousWindow.frame.minX, y: previousWindow.frame.maxY)
            window.cascadeTopLeft(from: topLeft)
        } else {
            window.center()
        }
        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func memoryDidCreate() {
        guard AppReviewPrompt.recordSuccessfulCreation() else { return }
        Task { [weak self] in
            try? await Task.sleep(for: AppReviewPrompt.presentationDelay)
            guard self?.windows.isEmpty == true, NSApp.isActive, let window = NSApp.keyWindow,
                  window.isVisible, window.attachedSheet == nil,
                  let controller = window.contentViewController else { return }
            AppReviewPrompt.requestIfEligible { AppStore.requestReview(in: controller) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === closed }
    }
}
#endif
