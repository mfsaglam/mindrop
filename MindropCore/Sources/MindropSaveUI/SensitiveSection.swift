#if os(iOS)
import SwiftUI

/// The "Sensitive" switch. Shared by the app's editor and the share sheet's save form.
/// Its footer says what Spotlight will show, so the warning about values in Spotlight
/// lives here, next to the way out of it.
public struct SensitiveSection: View {
    @Binding var isSensitive: Bool

    public init(isSensitive: Binding<Bool>) {
        _isSensitive = isSensitive
    }

    public var body: some View {
        Section {
            Toggle(isOn: $isSensitive) {
                Label {
                    localized("Sensitive")
                } icon: {
                    Image(systemName: "lock.fill")
                }
            }
        } footer: {
            if isSensitive {
                localized("Spotlight shows only the keyword, and Mindrop hides the value until you unlock it.")
            } else {
                localized("Saved values can show up directly in Spotlight search results, where anyone using this iPhone may see them.")
            }
        }
    }

    private func localized(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module)
    }
}
#endif
