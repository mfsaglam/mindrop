import Foundation
import Observation

/// The local order of memories selected for the Stack.
@available(watchOS 10.0, *)
@MainActor
@Observable
public final class MemoryStack {
    public enum SelectionError: Error, Equatable {
        case unavailableMemory
        case invalidOrder
    }

    private(set) var ids: [UUID] = []
    private let file: CoordinatedFile?

    public init(url: URL? = nil) {
        file = url.map { CoordinatedFile(url: $0) }
    }

    public func load() throws {
        guard let file else { return }
        ids = try Self.decode(file.read())
    }

    func setMembership(_ memoryIDs: [UUID], included: Bool) throws {
        guard !memoryIDs.isEmpty else { return }
        try update { order in
            if included {
                var known = Set(order)
                order += memoryIDs.filter { known.insert($0).inserted }
            } else {
                let removed = Set(memoryIDs)
                order.removeAll(where: removed.contains)
            }
        }
    }

    /// Reorder the visible entries in their slots, preserving temporarily hidden entries.
    func reorder(_ orderedIDs: [UUID]) throws {
        let reordered = Set(orderedIDs)
        try update { order in
            let positions = order.indices.filter { reordered.contains(order[$0]) }
            guard positions.count == orderedIDs.count else { throw SelectionError.invalidOrder }
            for (position, id) in zip(positions, orderedIDs) {
                order[position] = id
            }
        }
    }

    private func update(_ change: (inout [UUID]) throws -> Void) throws {
        guard let file else {
            try change(&ids)
            return
        }
        var updated: [UUID] = []
        try file.update { data in
            let previous = try Self.decode(data)
            updated = previous
            try change(&updated)
            return updated == previous ? nil : try JSONEncoder.mindrop.encode(updated)
        }
        ids = updated
    }

    private static func decode(_ data: Data?) throws -> [UUID] {
        guard let data else { return [] }
        return try JSONDecoder.mindrop.decode([UUID].self, from: data)
    }
}
