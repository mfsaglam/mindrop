import Foundation

/// The display-only copy of the Stack shared by Mindrop and the widget extension.
public struct StackWidgetSnapshot: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public let keyword: String
        public let value: String
        public let expiresAt: Date?

        public init(keyword: String, value: String, expiresAt: Date? = nil) {
            self.keyword = keyword
            self.value = value
            self.expiresAt = expiresAt
        }
    }

    public struct Frame: Sendable {
        public let date: Date
        public let records: [Record]
    }

    public static let lockScreenKind = "mfsaglam.Mindrop.Stack.LockScreen"
    public static let homeScreenKind = "mfsaglam.Mindrop.Stack.HomeScreen"
    public static let stackURL = URL(string: "mindrop://stack")!

    public static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.mfsaglam.Mindrop.widget")
            .map { $0.appending(path: "widget-stack.json") }
    }

    public let records: [Record]

    public init(records: [Record]) {
        self.records = records
    }

    public static func read(from url: URL?) -> Self? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public func visibleRecords(at date: Date, capacity: Int) -> [Record] {
        Array(records.lazy.filter { record in
            record.expiresAt.map { $0 > date } ?? true
        }.prefix(capacity))
    }

    /// Only expiry of an on-screen record can change the widget. Prepare the next
    /// states now so that a replacement already exists when the record expires.
    public func displayTimeline(startingAt date: Date, capacity: Int) -> (frames: [Frame], refreshAt: Date?) {
        var date = date
        var frames: [Frame] = []
        for _ in 0..<24 {
            let visible = visibleRecords(at: date, capacity: capacity)
            frames.append(Frame(date: date, records: visible))
            guard let nextExpiry = visible.compactMap(\.expiresAt).min() else { return (frames, nil) }
            date = nextExpiry
        }
        return (frames, frames.last?.date)
    }
}
