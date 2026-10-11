#if os(iOS)
import MindropCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Hosts the save form and bridges it to the extension context.
///
/// Both extensions subclass this and add nothing: a share extension and an action
/// extension receive the same `NSExtensionItem`s and do the same job, they only sit
/// in different rows of the share sheet.
open class SaveToMindropViewController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(
            rootView: SaveToMindropView(
                loadSharedValue: { [weak self] in await self?.sharedValue() },
                onFinish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                onCancel: { [weak self] in
                    self?.extensionContext?.cancelRequest(
                        withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                    )
                }
            )
        )

        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// The value to prefill, from whatever the host app put on the share sheet.
    private func sharedValue() async -> String? {
        var selectedText: [String?] = []
        var links: [String?] = []
        var hostDescription: [String?] = []

        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            hostDescription.append(item.attributedContentText?.string)
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    selectedText.append(await Self.load(UTType.plainText, from: provider))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    links.append(await Self.load(UTType.url, from: provider))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    selectedText.append(await Self.load(UTType.text, from: provider))
                }
            }
        }

        // Selected text first, then a shared link. The host's own description comes
        // last because for a page share that is the page title, not the link.
        return SharedTextParser.value(from: selectedText + links + hostDescription)
    }

    private static func load(_ type: UTType, from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                continuation.resume(returning: SharedTextParser.text(fromLoadedItem: item))
            }
        }
    }
}
#endif
