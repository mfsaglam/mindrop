#if os(iOS)
import MindropCore
import SwiftUI

/// The "Keep" row: forever, a day, a week, a month or until a date. Shared by the app's
/// editor and the share sheet's save form, so both offer the same choices in the same
/// words.
public struct MemoryLifetimeSection: View {
    @Binding var option: MemoryLifetime.Option
    @Binding var date: Date
    /// The earliest date the picker allows: now for a new memory, or an existing expiry
    /// that has already passed, so editing an expired memory does not move it.
    let earliestDate: Date

    public init(option: Binding<MemoryLifetime.Option>, date: Binding<Date>, earliestDate: Date = .now) {
        _option = option
        _date = date
        self.earliestDate = earliestDate
    }

    public var body: some View {
        Section {
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
            if option != .forever {
                localized("Leaves Spotlight when it expires. You can still recover it in Mindrop for 7 days.")
            }
        }
    }

    private func localized(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module)
    }
}
#endif
