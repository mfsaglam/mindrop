import Foundation

/// Reads and writes a single file in the App Group container under file coordination,
/// so the app and the share extension cannot tear each other's writes.
struct CoordinatedFile: Sendable {
    let url: URL

    /// Returns `nil` when the file does not exist yet.
    func read() throws -> Data? {
        var coordinatorError: NSError?
        var result: Result<Data?, Error> = .success(nil)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                result = .success(try Data(contentsOf: url))
            } catch {
                result = .failure(error)
            }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    func write(_ data: Data) throws {
        try coordinateWrite { url in try Self.write(data, to: url) }
    }

    func remove() throws {
        try coordinateWrite(options: .forDeleting) { url in try FileManager.default.removeItem(at: url) }
    }

    func update(_ transform: (Data?) throws -> Data?) throws {
        try coordinateWrite { url in
            let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            if let data = try transform(existing) { try Self.write(data, to: url) }
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private func coordinateWrite(
        options: NSFileCoordinator.WritingOptions = .forReplacing, _ action: (URL) throws -> Void
    ) throws {
        if options != .forDeleting {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinatorError) { url in
            do {
                try action(url)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }
}
