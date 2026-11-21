#if os(macOS)
import SwiftUI

struct MacMemoryCommands: Commands {
    let session: MindropSession
    @FocusedValue(\.findMemories) private var findMemories

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Memory") { session.showMacCapture() }
                .keyboardShortcut("n")
            Button("New Memory from Clipboard") { session.showMacCaptureFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find Memories…") { findMemories?() }
                .keyboardShortcut("f")
                .disabled(findMemories == nil)
        }
    }
}

extension FocusedValues {
    @Entry var findMemories: (() -> Void)?
}
#endif
