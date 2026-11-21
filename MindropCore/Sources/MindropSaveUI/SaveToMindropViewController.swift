#if os(iOS) || os(macOS)
import MindropCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
public typealias SharePlatformViewController = NSViewController
#else
import UIKit
public typealias SharePlatformViewController = UIViewController
#endif

/// Hosts the save form and bridges it to the extension context.
///
/// Both extensions subclass this and add nothing: a share extension and an action
/// extension receive the same `NSExtensionItem`s and do the same job, they only sit
/// in different rows of the share sheet.
@available(macOS 26.0, *)
open class SaveToMindropViewController: SharePlatformViewController {
    #if os(macOS)
    public override func loadView() {
        let host = NSHostingController(rootView: saveForm())
        addChild(host)
        view = host.view
        preferredContentSize = host.view.fittingSize
    }
    #else
    public override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: saveForm())

        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
    #endif

    private func saveForm() -> SaveToMindropView {
        SaveToMindropView(
            loadShared: { [weak self] in await self?.sharedContent() ?? SharedContent() },
            onFinish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(
                    withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                )
            }
        )
    }

    /// What the host app put on the share sheet: text to prefill the details with,
    /// and an image to read lines from.
    private func sharedContent() async -> SharedContent {
        var selectedText: [String?] = []
        var links: [String?] = []
        var hostDescription: [String?] = []
        #if os(iOS)
        var image: Data?
        #endif

        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            hostDescription.append(item.attributedContentText?.string)
            for provider in item.attachments ?? [] {
                #if os(macOS)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let raw = await Self.load(.url, from: provider),
                   let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https", url.host != nil {
                    links.append(raw)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    selectedText.append(await Self.load(.plainText, from: provider))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    selectedText.append(await Self.load(.text, from: provider))
                }
                #else
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    selectedText.append(await Self.load(UTType.plainText, from: provider))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    links.append(await Self.load(UTType.url, from: provider))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    selectedText.append(await Self.load(UTType.text, from: provider))
                } else if image == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    image = await Self.loadImage(from: provider)
                }
                #endif
            }
        }

        #if os(macOS)
        // Safari may also supply a page title as text. Prefer the actual web URL.
        return SharedContent(text: SharedTextParser.value(from: links + selectedText + hostDescription))
        #else
        // Selected text first, then a shared link. The host's own description comes
        // last because for a page share that is the page title, not the link. An image
        // usually arrives with no text at all; its caption, if any, is not the point.
        let text = image == nil ? selectedText + links + hostDescription : selectedText + links
        return SharedContent(text: SharedTextParser.value(from: text), image: image)
        #endif
    }

    #if os(iOS)
    /// The image's file data, whichever form the host offers it in (a file, a
    /// screenshot held in memory, raw bytes).
    private static func loadImage(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
    #endif

    private static func load(_ type: UTType, from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                continuation.resume(returning: SharedTextParser.text(fromLoadedItem: item))
            }
        }
    }
}
#endif
