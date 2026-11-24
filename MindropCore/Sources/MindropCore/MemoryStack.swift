import Foundation
import Observation

/// The local Stack order, with independent revisions for each memory's position.
@available(watchOS 10.0, *)
@MainActor
@Observable
public final class MemoryStack {
    public enum SelectionError: Error, Equatable {
        case unavailableMemory
        case invalidOrder
    }

    private(set) var positions: [UUID: LibraryStackPosition] = [:]
    private let file: CoordinatedFile?

    var ids: [UUID] { Self.ordered(positions).map(\.id) }

    func contains(_ id: UUID) -> Bool { positions[id]?.isIncluded == true }

    public init(url: URL? = nil) {
        file = url.map { CoordinatedFile(url: $0) }
    }

    public func load() throws {
        guard let file else { return }
        positions = try Self.decode(file.read())
    }

    func setMembership(_ memoryIDs: [UUID], included: Bool) throws {
        guard !memoryIDs.isEmpty else { return }
        try update { positions in
            if included {
                var rank = (Self.ordered(positions).last?.rank ?? -1) + 1
                for id in memoryIDs where positions[id]?.isIncluded != true {
                    let previous = positions[id]
                    positions[id] = LibraryStackPosition(
                        membership: .set(true, replacing: previous?.membership),
                        rank: .set(rank, replacing: previous?.rank)
                    )
                    rank += 1
                }
            } else {
                for id in memoryIDs {
                    guard var position = positions[id], position.isIncluded else { continue }
                    position.membership = .set(nil, replacing: position.membership)
                    positions[id] = position
                }
            }
        }
    }

    /// Reorder the visible entries in their slots, preserving temporarily hidden entries.
    func reorder(_ orderedIDs: [UUID]) throws {
        let reordered = Set(orderedIDs)
        try update { positions in
            let current = Self.ordered(positions)
            var order = current.map(\.id)
            let slots = order.indices.filter { reordered.contains(order[$0]) }
            guard slots.count == orderedIDs.count else { throw SelectionError.invalidOrder }
            for (slot, id) in zip(slots, orderedIDs) {
                order[slot] = id
            }
            guard order != current.map(\.id) else { return }
            // Two devices can append into the same slot. Break ties by UUID on read,
            // and give every item a unique slot when the user explicitly reorders.
            let ranks = current.map(\.rank)
            let distinctRanks = Set(ranks).count == ranks.count ? ranks : Array(order.indices)
            for (id, rank) in zip(order, distinctRanks) {
                guard var position = positions[id], position.rank.value != rank else { continue }
                position.rank = .set(rank, replacing: position.rank)
                positions[id] = position
            }
        }
    }

    func applyRemote(_ incoming: [UUID: LibraryStackPosition]) throws {
        guard !incoming.isEmpty else { return }
        try update { positions in
            positions.merge(incoming) { $0.merging($1) }
        }
    }

    private static func ordered(_ positions: [UUID: LibraryStackPosition]) -> [(id: UUID, rank: Int)] {
        positions.compactMap { id, position -> (id: UUID, rank: Int)? in
            guard position.isIncluded, let rank = position.rank.value else { return nil }
            return (id, rank)
        }
        .sorted { ($0.rank, $0.id.uuidString) < ($1.rank, $1.id.uuidString) }
    }

    private func update(_ change: (inout [UUID: LibraryStackPosition]) throws -> Void) throws {
        guard let file else {
            var updated = positions
            try change(&updated)
            if positions != updated { positions = updated }
            return
        }
        var updated = positions
        try file.update { data in
            let previous = try Self.decode(data)
            updated = previous
            try change(&updated)
            return updated == previous ? nil : try JSONEncoder.mindrop.encode(updated)
        }
        if positions != updated { positions = updated }
    }

    private static func decode(_ data: Data?) throws -> [UUID: LibraryStackPosition] {
        guard let data else { return [:] }
        let decoder = JSONDecoder.mindrop
        if let positions = try? decoder.decode([UUID: LibraryStackPosition].self, from: data) { return positions }
        let ids = try decoder.decode([UUID].self, from: data)
        return Dictionary(ids.enumerated().map { index, id in
            (id, LibraryStackPosition(membership: .legacy(true), rank: .legacy(index)))
        }, uniquingKeysWith: { first, _ in first })
    }
}
