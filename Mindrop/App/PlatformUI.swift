import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Clipboard {
    static func copy(_ value: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

extension View {
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct MemoryScreenBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
            .background {
                if colorScheme == .dark {
                    Color(.memoryScreenDarkBackground).ignoresSafeArea()
                }
            }
    }
}

extension View {
    func memoryScreenBackground() -> some View {
        modifier(MemoryScreenBackground())
    }
}
#endif

struct MemorySheetForm<Content: View>: View {
    #if os(iOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif
    @ViewBuilder var content: Content

    var body: some View {
        #if os(iOS)
        let rowBackground = colorScheme == .dark ? Color(.memorySheetDarkRowBackground) : nil
        Form {
            ForEach(sections: content) { section in
                Section {
                    ForEach(section.content) { row in
                        row.listRowBackground(rowBackground)
                    }
                } header: {
                    section.header
                } footer: {
                    section.footer
                }
            }
        }
        .memoryScreenBackground()
        #else
        Form { content }
        #endif
    }
}

extension ToolbarItemPlacement {
    static var memoryLeading: Self {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}
