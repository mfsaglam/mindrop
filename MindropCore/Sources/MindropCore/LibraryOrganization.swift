import Foundation

/// Local revisions belong to an individual folder, assignment, or Stack position.
/// A revision with no value is an explicit removal. An absent revision is unknown.
struct LibraryRevision: Codable, Comparable, Sendable {
    let milliseconds: Int64
    let operationID: UUID?

    static let legacy = Self(milliseconds: 0, operationID: nil)

    static func after(_ previous: Self?) -> Self {
        let now = Int64(Date.now.timeIntervalSince1970 * 1_000)
        return Self(milliseconds: max(now, (previous?.milliseconds ?? 0) + 1), operationID: UUID())
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.milliseconds != rhs.milliseconds { return lhs.milliseconds < rhs.milliseconds }
        return (lhs.operationID?.uuidString ?? "") < (rhs.operationID?.uuidString ?? "")
    }
}

struct LibraryChange<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let value: Value?
    let revision: LibraryRevision

    static func legacy(_ value: Value) -> Self {
        Self(value: value, revision: .legacy)
    }

    static func set(_ value: Value?, replacing previous: Self?) -> Self {
        Self(value: value, revision: .after(previous?.revision))
    }

    func merging(_ remote: Self) -> Self {
        revision > remote.revision ? self : remote
    }
}

struct LibraryFolderDetails: Codable, Equatable, Sendable {
    let name: String
    let order: Int
}

struct LibraryStackPosition: Codable, Equatable, Sendable {
    var membership: LibraryChange<Bool>
    var rank: LibraryChange<Int>

    var isIncluded: Bool { membership.value == true }

    func merging(_ remote: Self) -> Self {
        Self(membership: membership.merging(remote.membership), rank: rank.merging(remote.rank))
    }
}

struct LibraryRecordRevision: Codable, Equatable, Sendable {
    let value: LibraryRevision
    var rank: LibraryRevision? = nil
}

enum LibraryRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case folder
        case placement
        case stack
    }

    case folder(LibraryChange<LibraryFolderDetails>)
    case placement(LibraryChange<UUID>)
    case stack(LibraryStackPosition)

    var kind: Kind {
        switch self {
        case .folder: .folder
        case .placement: .placement
        case .stack: .stack
        }
    }

    var revision: LibraryRecordRevision {
        switch self {
        case .folder(let change): .init(value: change.revision)
        case .placement(let change): .init(value: change.revision)
        case .stack(let position): .init(value: position.membership.revision, rank: position.rank.revision)
        }
    }
}
