import Foundation
import Observation

/// The single owner of memories: persists them and keeps Spotlight in step.
///
/// Used by the app and, for saving, by the share extension. Not by the Apple Watch, which
/// keeps no library and runs as far back as watchOS 9.
@available(watchOS 10.0, *)
@MainActor
@Observable
public final class MemoryRepository {
    /// Most recently touched first.
    public private(set) var memories: [Memory] = [] {
        didSet { onStackContentChange?() }
    }

    /// The most recent background indexing work. Exposed so callers that must not
    /// outlive it — and tests — can wait for Spotlight to settle.
    public private(set) var indexingTask: Task<Void, Never>?

    /// The categorisation pass in progress, if any. Exposed for the same reason as
    /// `indexingTask`.
    public private(set) var categorizationTask: Task<Void, Never>?

    public let folders: MemoryFolders
    private let stack: MemoryStack

    private let store: MemoryStore
    private let synchronizer: SpotlightSynchronizer
    private let categorizer: (any MemoryCategorizing)?
    private let now: @Sendable () -> Date

    /// Called after every change made on this device, not after changes that came from
    /// iCloud. How iCloud sync learns there is something to send.
    public var onLocalChange: (() -> Void)?

    /// Re-evaluate the visible Stack after loading or persisting records or changing its order.
    public var onStackContentChange: (() -> Void)?

    /// Text the categorizer already declined this run, so a memory it cannot place is
    /// not sent again on every foregrounding. Keyed by content: an edit earns a retry.
    private var declinedCategorizations: Set<CategorizationKey> = []
    private var needsAnotherCategorizationPass = false

    public init(
        store: MemoryStore,
        synchronizer: SpotlightSynchronizer,
        categorizer: (any MemoryCategorizing)? = nil,
        folders: MemoryFolders = MemoryFolders(),
        stack: MemoryStack = MemoryStack(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.folders = folders
        self.stack = stack
        self.store = store
        self.synchronizer = synchronizer
        self.categorizer = categorizer
        self.now = now
        folders.onLocalChange = { [weak self] in self?.onLocalChange?() }
    }

    #if canImport(CoreSpotlight)
    /// The real configuration, shared by the app and the share extension. The extension
    /// passes no categorizer: it is torn down too quickly, and the app catches up on
    /// whatever it saved the next time it comes to the foreground.
    public static func live(
        categorizer: (any MemoryCategorizing)? = nil,
        spotlightExtras: SpotlightExtras = .none,
        folders: MemoryFolders = MemoryFolders(),
        stack: MemoryStack = MemoryStack()
    ) throws -> MemoryRepository {
        MemoryRepository(
            store: try FileMemoryStore.shared(),
            synchronizer: SpotlightSynchronizer(
                indexer: CoreSpotlightIndexer(extras: spotlightExtras),
                stateStore: try FileSpotlightSyncStateStore.shared()
            ),
            categorizer: categorizer,
            folders: folders,
            stack: stack
        )
    }
    #endif

    /// Re-reads storage. Called at launch and when returning to the foreground, since
    /// the share extension may have added memories in the meantime.
    public func load() throws {
        memories = try store.load().sorted(by: Self.isOrderedBefore)
    }

    #if os(macOS)
    public func importMacShares() throws {
        try importMacShares(from: MacShareInbox.file())
    }

    func importMacShares(from inbox: CoordinatedFile) throws {
        var imported: [Memory] = []
        defer {
            if !imported.isEmpty {
                onLocalChange?()
                indexInBackground(imported)
                categorizePending()
            }
        }
        try MacShareInbox.drain(from: inbox) { pending in
            var additions: [Memory] = []
            let updated = try store.update { stored in
                var knownIDs = Set(stored.map(\.id))
                additions = pending.filter { knownIDs.insert($0.id).inserted }
                guard !additions.isEmpty else { return nil }
                return (stored + additions).sorted(by: Self.isOrderedBefore)
            }
            if let updated {
                memories = updated
                imported = additions
            }
        }
    }
    #endif

    /// Finishes any Spotlight work left over from the last run. Call this after `load`,
    /// and never before showing the UI: talking to Core Spotlight can take seconds.
    public func resumeSpotlightSync() async {
        await synchronizer.resume(allMemories: memories.filter { !$0.isDeleted })
    }

    /// Records that the user opened or copied a memory: Spotlight ranks by it.
    public func recordUse(of memory: Memory) {
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.recordUse(of: memory) }
    }

    /// Checks that Spotlight holds every memory it should, and puts right what it lost.
    /// Nil if Spotlight could not be asked.
    public func checkSpotlight() async -> SpotlightCheck? {
        await synchronizer.verify(allMemories: memories.filter { !$0.isDeleted })
    }

    /// Indexes everything again from scratch, after the Spotlight options changed.
    public func reindexSpotlight() async {
        await synchronizer.reindexAll(memories.filter { !$0.isDeleted })
    }

    #if DEBUG
    /// Empties Spotlight without updating any record of it, as a restore would.
    public func simulateLostSpotlightIndex() async {
        await synchronizer.simulateLostIndex()
    }
    #endif

    public func memory(id: UUID) -> Memory? {
        memories.first { $0.id == id }
    }

    /// Captures the active library, including saves from the share extension.
    public func memoriesForBackup() throws -> [Memory] {
        let now = now()
        return try store.load().filter { !$0.isDeleted && !$0.isExpired(at: now) }
    }

    #if os(iOS) || os(macOS)
    public struct BackupDuplicate: Hashable, Identifiable, Sendable {
        public let id: UUID
        public let keyword: String
        public let originalFolderID: UUID
        let originalID: UUID
    }

    private struct BackupDuplicateContent: Hashable {
        let createdAt: TimeInterval
        let keyword: String
        let value: String
        let expiresAt: Date?
        let isSensitive: Bool
        let manualCategory: MemoryCategory?

        init(_ memory: Memory) {
            // Older local stores persisted creation dates to whole seconds.
            createdAt = memory.createdAt.timeIntervalSinceReferenceDate.rounded(.down)
            keyword = memory.keyword
            value = memory.value
            expiresAt = memory.expiresAt
            isSensitive = memory.isSensitive
            manualCategory = memory.category?.source == .manual ? memory.category?.category : nil
        }
    }

    public var backupDuplicates: [BackupDuplicate] {
        backupDuplicates(in: memories, at: now())
    }

    public func deleteBackupDuplicates(_ approved: [BackupDuplicate]) throws -> Int {
        try folders.load()
        let approved = Set(approved)
        return try moveToRecentlyDeleted { stored, date in
            Set(backupDuplicates(in: stored, at: date).filter(approved.contains).map(\.id))
        }
    }

    private func backupDuplicates(in stored: [Memory], at date: Date) -> [BackupDuplicate] {
        let active = stored.filter { !$0.isDeleted && !$0.isExpired(at: date) }
        let groups = Dictionary(grouping: active, by: BackupDuplicateContent.init)
        return groups.values.flatMap { group -> [BackupDuplicate] in
            guard group.count > 1, let original = group.min(by: { lhs, rhs in
                (backupDuplicatePriority(lhs.id), lhs.updatedAt, lhs.id.uuidString)
                    < (backupDuplicatePriority(rhs.id), rhs.updatedAt, rhs.id.uuidString)
            }) else { return [] }
            let folderID = folders.folderID(for: original.id)
            return group.compactMap { copy in
                // Legacy restores kept createdAt but wrote the restore time to updatedAt.
                // Offer only unfiled copies without any explicit placement or Stack membership.
                guard copy.id != original.id, backupDuplicatePriority(copy.id) == 2,
                      copy.updatedAt.timeIntervalSince(copy.createdAt) >= 1,
                      folderID != MemoryFolders.generalID || copy.updatedAt > original.updatedAt else { return nil }
                return BackupDuplicate(id: copy.id, keyword: copy.keyword, originalFolderID: folderID, originalID: original.id)
            }
        }.sorted { ($0.keyword, $0.id.uuidString) < ($1.keyword, $1.id.uuidString) }
    }

    private func backupDuplicatePriority(_ id: UUID) -> Int {
        if folders.folderID(for: id) != MemoryFolders.generalID { return 0 }
        return folders.placements[id] != nil || stack.contains(id) ? 1 : 2
    }

    public func driveBackupLibrary() throws -> DriveBackupLibrary {
        try folders.load()
        let memories = try memoriesForBackup()
        let members = Dictionary(grouping: memories.map(\.id), by: folders.folderID(for:))
        let folders = folders.custom.map { folder in
            DriveBackupLibrary.Folder(id: folder.id, name: folder.name, memoryIDs: members[folder.id] ?? [])
        }
        return DriveBackupLibrary(memories: memories, folders: folders)
    }

    /// First-install recovery keeps the original IDs so iCloud Sync can match its records.
    public func recoverDriveBackup(_ snapshot: DriveBackupSnapshot) throws {
        let now = now()
        let active = snapshot.library.memories.filter { !$0.isDeleted && !$0.isExpired(at: now) }
        let updated = try store.update { stored in
            guard stored.isEmpty else { return nil }
            let ids = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0.id) })
            try folders.restore(snapshot.library.folders, memoryIDs: ids)
            return active.sorted(by: Self.isOrderedBefore)
        }
        finishBackupRestore(updated, indexing: active)
    }

    /// Restores missing entries by ID and adds older versions of existing entries as copies.
    @discardableResult
    public func restoreDriveBackup(_ snapshot: DriveBackupSnapshot) throws -> Int {
        let library = snapshot.library
        let backup = MemoryBackup(id: snapshot.id, createdAt: snapshot.createdAt, memoryCount: library.memories.count)

        var restored: [Memory] = []
        let now = now()
        let previousDefinitions = folders.definitions
        let previousPlacements = folders.placements
        let updated = try store.update { stored in
            restored = Self.restoredMemories(
                from: library.memories, in: backup, alongside: stored, now: now, keepingMissingIDs: true
            )
            guard !library.folders.isEmpty else {
                return restored.isEmpty ? nil : (stored + restored).sorted(by: Self.isOrderedBefore)
            }
            let active = (stored + restored).filter { !$0.isDeleted && !$0.isExpired(at: now) }
            let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var destinations: [UUID: UUID] = [:]
            for memory in library.memories where !memory.isDeleted && !memory.isExpired(at: now) {
                let copyID = backup.restoredID(for: memory.id)
                if let existing = byID[memory.id], Self.matchesDriveBackup(memory, existing: existing) {
                    destinations[memory.id] = memory.id
                } else if let copy = byID[copyID], Self.matchesDriveBackup(memory, existing: copy) {
                    destinations[memory.id] = copyID
                }
            }
            try folders.restore(library.folders, memoryIDs: destinations, restoredFolderID: backup.restoredID(for:))
            return restored.isEmpty ? nil : (stored + restored).sorted(by: Self.isOrderedBefore)
        }
        finishBackupRestore(updated, indexing: restored)
        if updated == nil, previousDefinitions != folders.definitions || previousPlacements != folders.placements {
            onLocalChange?()
        }
        return restored.count
    }
    #endif

    /// Restores earlier or missing entries as copies, preserving the current library.
    @discardableResult
    public func restore(_ snapshot: [Memory], from backup: MemoryBackup) throws -> Int {
        var restored: [Memory] = []
        let updated = try store.update { stored in
            restored = Self.restoredMemories(from: snapshot, in: backup, alongside: stored, now: now())
            guard !restored.isEmpty else { return nil }
            return (stored + restored).sorted(by: Self.isOrderedBefore)
        }
        finishBackupRestore(updated, indexing: restored)
        return restored.count
    }

    private func finishBackupRestore(_ updated: [Memory]?, indexing restored: [Memory]) {
        guard let updated else { return }
        memories = updated
        onLocalChange?()
        indexInBackground(restored)
        categorizePending()
    }

    private static func restoredMemories(
        from snapshot: [Memory], in backup: MemoryBackup, alongside stored: [Memory], now: Date,
        keepingMissingIDs: Bool = false
    ) -> [Memory] {
        let current = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var knownIDs = Set(current.keys)
        var restored: [Memory] = []
        for memory in snapshot where !memory.isDeleted && !memory.isExpired(at: now) {
            let existing = current[memory.id]
            let id = backup.restoredID(for: memory.id)
            if keepingMissingIDs, existing == nil {
                // This file may already have been restored as copies by an older version.
                guard !knownIDs.contains(id), knownIDs.insert(memory.id).inserted else { continue }
                restored.append(memory)
                continue
            }
            if let existing {
                let alreadyRestored = keepingMissingIDs
                    ? Self.matchesDriveBackup(memory, existing: existing)
                    : Self.matchesBackup(memory, existing: existing)
                if alreadyRestored { continue }
            }
            guard knownIDs.insert(id).inserted else { continue }
            restored.append(Memory(
                id: id,
                keyword: memory.keyword,
                value: memory.value,
                createdAt: memory.createdAt,
                updatedAt: now,
                category: memory.category,
                expiresAt: memory.expiresAt,
                isSensitive: memory.isSensitive || (existing?.isSensitive ?? false)
            ))
        }
        return restored
    }

    private static func matchesBackup(_ memory: Memory, existing: Memory) -> Bool {
        matchesBackupContent(memory, existing: existing) && existing.category == memory.category
    }

    private static func matchesDriveBackup(_ memory: Memory, existing: Memory) -> Bool {
        matchesBackupContent(memory, existing: existing)
            && (memory.category?.source != .manual || existing.category == memory.category)
    }

    private static func matchesBackupContent(_ memory: Memory, existing: Memory) -> Bool {
        !existing.isDeleted && existing.keyword == memory.keyword && existing.value == memory.value
            && existing.expiresAt == memory.expiresAt && (existing.isSensitive || !memory.isSensitive)
    }

    /// In-app filtering, newest first. An empty query and no category return every memory
    /// that has not expired or been deleted.
    public func results(
        for query: String, in category: MemoryCategory? = nil, folderID: UUID? = nil
    ) -> [Memory] {
        let now = now()
        return memories.filter { memory in
            !memory.isExpired(at: now) && !memory.isDeleted
                && (category == nil || memory.category?.category == category)
                && (folderID == nil || folders.folderID(for: memory.id) == folderID)
                && memory.matches(query: query)
        }
    }

    /// Expired memories matching the query, most recently expired first. Kept apart from
    /// `results` so they can be recovered but never get in the way.
    public func expiredResults(for query: String, folderID: UUID? = nil) -> [Memory] {
        let now = now()
        return memories
            .filter { memory in
                memory.isExpired(at: now) && !memory.isDeleted
                    && (folderID == nil || folders.folderID(for: memory.id) == folderID)
                    && memory.matches(query: query)
            }
            .sorted { ($0.expiresAt ?? .distantPast) > ($1.expiresAt ?? .distantPast) }
    }

    /// Recently Deleted, most recently deleted first.
    public var deletedMemories: [Memory] {
        memories
            .filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// The categories at least one live memory is in, in declaration order — what a
    /// filter offers.
    public var categoriesInUse: [MemoryCategory] {
        categories(in: nil)
    }

    public func categories(in folderID: UUID?) -> [MemoryCategory] {
        let used = Set(results(for: "", folderID: folderID).compactMap(\.category?.category))
        return MemoryCategory.allCases.filter(used.contains)
    }

    public func move(_ memory: Memory, to folderID: UUID) throws {
        try move(ids: [memory.id], to: folderID)
    }

    /// Moves existing, non-deleted memories in one folder index update.
    public func move(ids: [UUID], to folderID: UUID) throws {
        guard !ids.isEmpty else { return }
        let selection = Set(ids)
        let movable = memories.filter { selection.contains($0.id) && !$0.isDeleted }.map(\.id)
        guard !movable.isEmpty else { return }
        try folders.assign(movable, to: folderID)
    }

    /// Removes a custom folder and sends its memories through the usual recoverable deletion flow.
    public func deleteFolder(_ id: UUID) throws {
        try folders.remove(id) { try delete(ids: $0) }
    }

    public var stackMemories: [Memory] {
        let ids = stack.ids
        guard !ids.isEmpty else { return [] }
        let selected = Set(ids)
        let now = now()
        let visible = memories.lazy.filter {
            selected.contains($0.id) && !$0.isSensitive && !$0.isDeleted && !$0.isExpired(at: now)
        }
        let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    public func stackCandidates(matching query: String) -> [Memory] {
        let selected = Set(stack.ids)
        return results(for: query).filter { !$0.isSensitive && !selected.contains($0.id) }
    }

    public func isInStack(_ id: UUID) -> Bool { stack.contains(id) }

    public func isEligibleForStack(_ memory: Memory) -> Bool {
        !memory.isSensitive && !memory.isDeleted && !memory.isExpired(at: now())
    }

    public func setStackMembership(_ ids: [UUID], included: Bool) throws {
        if included {
            let eligible = Set(results(for: "").filter { !$0.isSensitive }.map(\.id))
            guard eligible.isSuperset(of: ids) else { throw MemoryStack.SelectionError.unavailableMemory }
        }
        try stack.setMembership(ids, included: included)
        onStackContentChange?()
        onLocalChange?()
    }

    public func reorderStack(_ orderedIDs: [UUID]) throws {
        let visible = Set(stackMemories.map(\.id))
        guard orderedIDs.count == visible.count, Set(orderedIDs) == visible else {
            throw MemoryStack.SelectionError.invalidOrder
        }
        try stack.reorder(orderedIDs)
        onStackContentChange?()
        onLocalChange?()
    }

    var libraryRevisions: [CloudLibraryRecord.ID: LibraryRecordRevision] {
        var revisions: [CloudLibraryRecord.ID: LibraryRecordRevision] = [:]
        for (id, change) in folders.definitions {
            revisions[.init(kind: .folder, uuid: id)] = LibraryRecord.folder(change).revision
        }
        for (id, change) in folders.placements {
            revisions[.init(kind: .placement, uuid: id)] = LibraryRecord.placement(change).revision
        }
        for (id, change) in stack.positions {
            revisions[.init(kind: .stack, uuid: id)] = LibraryRecord.stack(change).revision
        }
        return revisions
    }

    func libraryRecord(for id: CloudLibraryRecord.ID) -> LibraryRecord? {
        switch id.kind {
        case .folder: folders.definitions[id.uuid].map(LibraryRecord.folder)
        case .placement: folders.placements[id.uuid].map(LibraryRecord.placement)
        case .stack: stack.positions[id.uuid].map(LibraryRecord.stack)
        }
    }

    func applyRemoteLibrary(_ records: [CloudLibraryRecord.ID: LibraryRecord]) throws {
        var definitions: [UUID: LibraryChange<LibraryFolderDetails>] = [:]
        var placements: [UUID: LibraryChange<UUID>] = [:]
        var positions: [UUID: LibraryStackPosition] = [:]
        for (id, record) in records {
            switch record {
            case .folder(let change): definitions[id.uuid] = change
            case .placement(let change): placements[id.uuid] = change
            case .stack(let change): positions[id.uuid] = change
            }
        }
        try folders.applyRemote(definitions: definitions, placements: placements)
        let previousStack = stack.positions
        try stack.applyRemote(positions)
        if stack.positions != previousStack { onStackContentChange?() }
    }

    @discardableResult
    public func create(
        keyword: String, value: String, expiresAt: Date? = nil, isSensitive: Bool = false,
        folderID: UUID = MemoryFolders.generalID, addsToStack: Bool = false
    ) throws -> Memory {
        let memory = try insert(
            keyword: keyword, value: value, expiresAt: expiresAt, isSensitive: isSensitive,
            folderID: folderID, addsToStack: addsToStack
        )
        indexInBackground([memory])
        categorizePending()
        return memory
    }

    /// Creates a memory and waits for Spotlight to accept it.
    ///
    /// The share extension is torn down as soon as it completes its request, so it
    /// cannot leave indexing running in the background the way the app can.
    @discardableResult
    public func createAwaitingIndex(
        keyword: String,
        value: String,
        expiresAt: Date? = nil,
        isSensitive: Bool = false
    ) async throws -> Memory {
        let memory = try insert(keyword: keyword, value: value, expiresAt: expiresAt, isSensitive: isSensitive)
        await synchronizer.index([memory])
        return memory
    }

    private func insert(
        keyword: String, value: String, expiresAt: Date?, isSensitive: Bool,
        folderID: UUID = MemoryFolders.generalID, addsToStack: Bool = false
    ) throws -> Memory {
        let memory = try Memory.make(
            keyword: keyword,
            value: value,
            now: now(),
            expiresAt: expiresAt,
            isSensitive: isSensitive
        )
        if addsToStack, !isEligibleForStack(memory) { throw MemoryStack.SelectionError.unavailableMemory }
        let isCustom = folderID != MemoryFolders.generalID
        if isCustom { try folders.assign(memory.id, to: folderID) }
        do {
            if addsToStack { try stack.setMembership([memory.id], included: true) }
            // The share extension may have saved since the app last refreshed its list.
            let stored = try store.update { ($0 + [memory]).sorted(by: Self.isOrderedBefore) }
            if let stored { memories = stored }
        } catch {
            if addsToStack { try? stack.setMembership([memory.id], included: false) }
            if isCustom { try? folders.assign(memory.id, to: MemoryFolders.generalID) }
            throw error
        }
        onLocalChange?()
        return memory
    }

    /// Saves an edit of the text, keeping the memory's expiry and sensitivity.
    @discardableResult
    public func update(_ memory: Memory, keyword: String, value: String) throws -> Memory {
        try update(memory, keyword: keyword, value: value, expiresAt: memory.expiresAt, isSensitive: memory.isSensitive)
    }

    /// Saves an edit. Returns the stored memory, unchanged if nothing differed.
    @discardableResult
    public func update(
        _ memory: Memory,
        keyword: String,
        value: String,
        expiresAt: Date?,
        isSensitive: Bool
    ) throws -> Memory {
        let edited = try memory.updating(
            keyword: keyword,
            value: value,
            expiresAt: expiresAt,
            isSensitive: isSensitive,
            now: now()
        )
        guard edited != memory, let position = memories.firstIndex(where: { $0.id == memory.id }) else {
            return memory
        }
        var updated = memories
        updated[position] = edited
        try commit(updated)
        indexInBackground([edited])
        categorizePending()
        return edited
    }

    /// Files a memory under a category the user picked, or with `nil` hands it back to
    /// the categorizer. Not an edit: the memory keeps its place in the list. Reindexed,
    /// since Spotlight shows the category's icon.
    public func setCategory(_ category: MemoryCategory?, for memory: Memory) throws {
        var stored = try store.load()
        guard let position = stored.firstIndex(where: { $0.id == memory.id }) else { return }
        stored[position].category = category.map { CategoryAssignment(category: $0, source: .manual) }
        stored[position].modifiedAt = now()
        try commit(stored)
        if synchronizer.indexesCategory { indexInBackground([stored[position]]) }
        if category == nil {
            declinedCategorizations.remove(CategorizationKey(stored[position]))
            categorizePending()
        }
    }

    /// Drops every automatic category and categorises everything again. Manual choices
    /// stay. For trying out a changed prompt without bumping the categorizer version.
    public func resetAutomaticCategories() throws {
        var stored = try store.load()
        for position in stored.indices where stored[position].category?.source == .automatic {
            stored[position].category = nil
            stored[position].modifiedAt = now()
        }
        try commit(stored)
        declinedCategorizations.removeAll()
        categorizePending()
    }

    /// Categorises every memory that has no category yet, or one from an older categorizer. Cheap to call often: it does
    /// nothing without a categorizer, and coalesces with a pass already running.
    public func categorizePending() {
        guard let categorizer else { return }
        guard categorizationTask == nil else {
            needsAnotherCategorizationPass = true
            return
        }
        categorizationTask = Task {
            await categorizeUntilSettled(using: categorizer)
            categorizationTask = nil
        }
    }

    private func categorizeUntilSettled(using categorizer: any MemoryCategorizing) async {
        repeat {
            needsAnotherCategorizationPass = false
            let pending = memories.filter {
                !$0.isDeleted
                    && $0.needsCategory(categorizerVersion: categorizer.version)
                    && !declinedCategorizations.contains(CategorizationKey($0))
            }
            for memory in pending {
                if let category = await categorizer.category(for: memory) {
                    // Nothing to do if this fails: the memory stays uncategorised and the
                    // next pass tries again.
                    try? apply(category, version: categorizer.version, to: memory)
                } else {
                    declinedCategorizations.insert(CategorizationKey(memory))
                }
            }
        } while needsAnotherCategorizationPass
    }

    /// Stores an automatic category, unless the memory changed while the model was
    /// thinking. Reads storage first so it cannot overwrite what the share extension
    /// saved in the meantime.
    private func apply(_ category: MemoryCategory, version: Int, to original: Memory) throws {
        var stored = try store.load()
        guard let position = stored.firstIndex(where: { $0.id == original.id }),
              CategorizationKey(stored[position]) == CategorizationKey(original),
              stored[position].needsCategory(categorizerVersion: version)
        else { return }
        stored[position].category = CategoryAssignment(category: category, source: .automatic, version: version)
        stored[position].modifiedAt = now()
        try commit(stored)
        if synchronizer.indexesCategory { indexInBackground([stored[position]]) }
    }

    /// Moves a memory's expiry, or with `nil` keeps it forever. Recovering an expired
    /// memory is this with `nil`: it comes back for good, not on a new timer. Reindexed,
    /// because Spotlight drops an item at its expiry.
    public func setExpiry(_ expiresAt: Date?, for memory: Memory) throws {
        guard let current = self.memory(id: memory.id) else { return }
        try update(
            current,
            keyword: current.keyword,
            value: current.value,
            expiresAt: expiresAt,
            isSensitive: current.isSensitive
        )
    }

    /// Hides a memory's value from Spotlight, or shows it there again. Reindexed, since
    /// that is the whole point; not an edit, so the memory keeps its place in the list.
    public func setSensitive(_ isSensitive: Bool, for memory: Memory) throws {
        guard let current = self.memory(id: memory.id) else { return }
        try update(
            current,
            keyword: current.keyword,
            value: current.value,
            expiresAt: current.expiresAt,
            isSensitive: isSensitive
        )
    }

    /// Deletes for good every memory past its retention: expired more than 7 days ago, or
    /// in Recently Deleted for more than 30 days. Call at launch and on returning to the
    /// foreground.
    public func purge() throws {
        let now = now()
        try deletePermanently(ids: memories.filter { $0.isDueForDeletion(at: now) }.map(\.id))
    }

    /// Moves memories to Recently Deleted: out of the list and out of Spotlight, and
    /// deleted for good 30 days later unless recovered.
    public func delete(ids: [UUID]) throws {
        let doomed = Set(ids)
        guard !doomed.isEmpty else { return }
        try moveToRecentlyDeleted { _, _ in doomed }
    }

    @discardableResult
    private func moveToRecentlyDeleted(_ selection: ([Memory], Date) -> Set<UUID>) throws -> Int {
        let now = now()
        var moved: [UUID] = []
        // Read and write under the same coordination so a concurrent share save survives.
        let updated = try store.update { stored in
            let doomed = selection(stored, now)
            var updated = stored
            for position in updated.indices where doomed.contains(updated[position].id) && !updated[position].isDeleted {
                updated[position].deletedAt = now
                updated[position].modifiedAt = now
                moved.append(updated[position].id)
            }
            return moved.isEmpty ? nil : updated.sorted(by: Self.isOrderedBefore)
        }
        guard let updated else { return 0 }
        memories = updated
        onLocalChange?()
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.remove(ids: moved) }
        return moved.count
    }

    /// Brings a memory back from Recently Deleted, into Spotlight again. An expired one
    /// goes back to the Expired section.
    public func recoverDeleted(_ memory: Memory) throws {
        guard let position = memories.firstIndex(where: { $0.id == memory.id }), memories[position].isDeleted else {
            return
        }
        var updated = memories
        updated[position].deletedAt = nil
        updated[position].modifiedAt = now()
        try commit(updated)
        indexInBackground([updated[position]])
    }

    /// Deletes for good, here and, through iCloud, on every device. Recently Deleted's
    /// Delete Now, and the end of every retention.
    public func deletePermanently(ids: [UUID]) throws {
        let doomed = Set(ids)
        guard memories.contains(where: { doomed.contains($0.id) }) else { return }
        try commit(memories.filter { !doomed.contains($0.id) })
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.remove(ids: ids) }
    }

    /// Takes in what iCloud sent: changed memories, merged with this device's own version
    /// (`Memory.merged`), and memories deleted for good elsewhere. Returns what is now
    /// stored for each changed id. Not reported through `onLocalChange`.
    @discardableResult
    public func applyRemote(_ remote: [Memory], deletedIDs: [UUID]) throws -> [UUID: Memory] {
        // From storage, so a save from the share extension is merged, not overwritten.
        var stored = try store.load()
        var result: [UUID: Memory] = [:]
        var changed: [Memory] = []
        for incoming in remote {
            if let position = stored.firstIndex(where: { $0.id == incoming.id }) {
                let merged = Memory.merged(local: stored[position], remote: incoming)
                if merged != stored[position] {
                    stored[position] = merged
                    changed.append(merged)
                }
                result[incoming.id] = merged
            } else {
                stored.append(incoming)
                changed.append(incoming)
                result[incoming.id] = incoming
            }
        }
        let doomed = Set(deletedIDs)
        let removed = stored.filter { doomed.contains($0.id) }.map(\.id)
        stored.removeAll { doomed.contains($0.id) }
        guard !changed.isEmpty || !removed.isEmpty else { return result }

        try commit(stored, isLocal: false)
        let toIndex = changed.filter { !$0.isDeleted }
        let toRemove = changed.filter(\.isDeleted).map(\.id) + removed
        let synchronizer = synchronizer
        indexingTask = Task {
            await synchronizer.remove(ids: toRemove)
            await synchronizer.index(toIndex)
        }
        categorizePending()
        return result
    }

    private func commit(_ updated: [Memory], isLocal: Bool = true) throws {
        let sorted = updated.sorted(by: Self.isOrderedBefore)
        try store.save(sorted)
        memories = sorted
        if isLocal { onLocalChange?() }
    }

    /// A deleted memory is never indexed, whatever else changed about it.
    private func indexInBackground(_ memories: [Memory]) {
        let live = memories.filter { !$0.isDeleted }
        guard !live.isEmpty else { return }
        let synchronizer = synchronizer
        indexingTask = Task { await synchronizer.index(live) }
    }

    private struct CategorizationKey: Hashable {
        let id: UUID
        let keyword: String
        let value: String

        init(_ memory: Memory) {
            id = memory.id
            keyword = memory.keyword
            value = memory.value
        }
    }

    private static func isOrderedBefore(_ lhs: Memory, _ rhs: Memory) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.keyword.localizedCaseInsensitiveCompare(rhs.keyword) == .orderedAscending
    }
}
