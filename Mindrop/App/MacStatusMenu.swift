#if os(macOS)
import AppKit
import SwiftUI

struct MacStatusMenu: View {
    static let libraryID = "library"

    let session: MindropSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Memory") { session.showMacCapture() }
        Button("New Memory from Clipboard") { session.showMacCaptureFromClipboard() }
        Divider()
        Button("Open Mindrop") {
            NSApp.activate()
            openWindow(id: Self.libraryID, value: true)
        }
    }
}
#endif
