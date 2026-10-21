import Foundation

/// How long a memory is kept, as the user picks it when saving.
///
/// Fixed steps rather than a free duration: a hotel room, a parking spot or a guest
/// Wi-Fi password never needs more precision than this, and a date covers the rest.
public enum MemoryLifetime: Hashable, Sendable {
    case forever
    case day
    case week
    case month
    case until(Date)

    /// How long an expired memory stays under Expired, recoverable, before it is
    /// deleted for good.
    public static let expiredRetention: TimeInterval = 7 * 24 * 60 * 60

    /// The expiry this lifetime gives a memory saved at `now`; nil for forever.
    public func expiry(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .forever: nil
        case .day: calendar.date(byAdding: .day, value: 1, to: now)
        case .week: calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        case .month: calendar.date(byAdding: .month, value: 1, to: now)
        case .until(let date): date
        }
    }
}

public extension MemoryLifetime {
    /// What a picker offers. `date` stands for `until`, whose date the picker keeps apart.
    enum Option: Hashable, Sendable, CaseIterable {
        case forever, day, week, month, date
    }

    init(_ option: Option, until date: Date) {
        switch option {
        case .forever: self = .forever
        case .day: self = .day
        case .week: self = .week
        case .month: self = .month
        case .date: self = .until(date)
        }
    }
}
