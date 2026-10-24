#if os(iOS)
import MindropCore
import SwiftUI

/// Sensitive and Keep, in one section: most memories use neither. Shared by the app's
/// editor and the share sheet's save form, so both offer the same choices in the same
/// words.
///
/// The footer says what Spotlight will show: the line itself once there is a keyword and
/// details, and that anyone using the iPhone may see it, next to the switch that prevents
/// it.
public struct MemoryOptionsSection: View {
    let keyword: String
    let value: String
    @Binding var isSensitive: Bool
    @Binding var option: MemoryLifetime.Option
    @Binding var date: Date
    /// The earliest date the picker allows: now for a new memory, or an existing expiry
    /// that has already passed, so editing an expired memory does not move it.
    let earliestDate: Date

    public init(
        keyword: String,
        value: String,
        isSensitive: Binding<Bool>,
        option: Binding<MemoryLifetime.Option>,
        date: Binding<Date>,
        earliestDate: Date = .now
    ) {
        self.keyword = keyword
        self.value = value
        _isSensitive = isSensitive
        _option = option
        _date = date
        self.earliestDate = earliestDate
    }

    /// The line Spotlight will show, as it is built for the index. Nil until both fields
    /// hold something.
    private var spotlightLine: String? {
        let keyword = MemoryNormalizer.normalizeKeyword(keyword)
        let value = MemoryNormalizer.normalizeValue(value)
        guard !keyword.isEmpty, !value.isEmpty else { return nil }
        let draft = Memory(keyword: keyword, value: value, createdAt: .now, updatedAt: .now)
        return SpotlightAttributesFactory.make(for: draft).displayName
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
            Picker(selection: $option) {
                localized("Forever").tag(MemoryLifetime.Option.forever)
                localized("1 Day").tag(MemoryLifetime.Option.day)
                localized("1 Week").tag(MemoryLifetime.Option.week)
                localized("1 Month").tag(MemoryLifetime.Option.month)
                localized("Until a Date").tag(MemoryLifetime.Option.date)
            } label: {
                localized("Keep")
            }
            if option == .date {
                DatePicker(selection: $date, in: min(earliestDate, date)..., displayedComponents: .date) {
                    localized("Until")
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if isSensitive {
                    localized("Spotlight shows only the keyword, and Mindrop hides the value until you unlock it.")
                } else if let spotlightLine {
                    // The line is user content: interpolated, never looked up.
                    Text("Shows in Spotlight as “\(spotlightLine)”, where anyone using this iPhone may see it.", bundle: .module)
                } else {
                    localized("Saved values can show up directly in Spotlight search results, where anyone using this iPhone may see them.")
                }
                if option != .forever {
                    localized("Leaves Spotlight when it expires. You can still recover it in Mindrop for 7 days.")
                }
            }
        }
    }

    private func localized(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module)
    }
}
#endif
