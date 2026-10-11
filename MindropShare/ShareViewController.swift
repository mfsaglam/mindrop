import MindropCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Hosts the share sheet UI and bridges it to the extension context.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(
            rootView: ShareView(
                loadSharedValue: { [weak self] in await self?.sharedText() },
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

    /// Text the host app put on the share sheet, from the attributed content text or
    /// a plain-text attachment. Only text is accepted, as declared in Info.plist.
    private func sharedText() async -> String? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var candidates: [String?] = []
        for item in items {
            candidates.append(item.attributedContentText?.string)
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                candidates.append(await Self.text(from: provider))
            }
        }
        return SharedTextParser.value(from: candidates)
    }

    private static func text(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.text.identifier) { item, _ in
                switch item {
                case let string as String:
                    continuation.resume(returning: string)
                case let attributed as NSAttributedString:
                    continuation.resume(returning: attributed.string)
                case let data as Data:
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
