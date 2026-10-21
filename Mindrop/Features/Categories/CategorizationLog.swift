import Foundation
import MindropCore
import Observation

/// Every categorisation request this launch, for the debug screen. Kept in memory only
/// and never in Release builds: it holds keywords and the start of each value, except
/// for sensitive memories, whose value is left out.
@MainActor
@Observable
final class CategorizationLog {
    enum Outcome: Equatable {
        /// Decided by a rule; the model was not asked.
        case rule(MemoryCategory)
        case model(MemoryCategory)
        /// The model replied with something that names no category.
        case unparsed
        case failed(String)
        case unavailable(String)

        var category: MemoryCategory? {
            switch self {
            case .rule(let category), .model(let category): category
            default: nil
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let memoryID: UUID
        let keyword: String
        let date: Date
        let duration: TimeInterval
        let prompt: String
        let response: String?
        let outcome: Outcome
    }

    /// Newest first.
    private(set) var entries: [Entry] = []

    /// Plenty for a debugging session, without growing for ever.
    private let limit = 1_000

    func record(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    func clear() {
        entries.removeAll()
    }

    /// Entries per memory, the memory with the latest request first.
    var byMemory: [(memoryID: UUID, entries: [Entry])] {
        var order: [UUID] = []
        var groups: [UUID: [Entry]] = [:]
        for entry in entries {
            if groups[entry.memoryID] == nil { order.append(entry.memoryID) }
            groups[entry.memoryID, default: []].append(entry)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}
