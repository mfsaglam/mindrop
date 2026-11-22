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
    let usesGradient: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(colorScheme == .dark ? .hidden : .automatic)
            .background {
                if colorScheme == .dark {
                    darkBackground.ignoresSafeArea()
                }
            }
    }

    @ViewBuilder
    private var darkBackground: some View {
        if usesGradient {
            LinearGradient(
                stops: [
                    .init(color: Color(.memoryScreenDarkGradientStart), location: 0),
                    .init(color: Color(.memoryScreenDarkBackground), location: 0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.memoryScreenDarkBackground)
        }
    }
}

extension View {
    func memoryScreenBackground(usesGradient: Bool = false) -> some View {
        modifier(MemoryScreenBackground(usesGradient: usesGradient))
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
