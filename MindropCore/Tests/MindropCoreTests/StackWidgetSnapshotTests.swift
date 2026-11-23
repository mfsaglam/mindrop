import Foundation
import MindropWidgetData
import Testing

@Suite("Stack widget snapshot")
struct StackWidgetSnapshotTests {
    @Test("Only visible expiry dates produce timeline entries and promote the next eligible record")
    func expiryTimeline() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let firstExpiry = now.addingTimeInterval(900)
        let secondExpiry = now.addingTimeInterval(1_800)
        let snapshot = StackWidgetSnapshot(records: [
            .init(keyword: "Gate", value: "C24", expiresAt: firstExpiry),
            .init(keyword: "Seat", value: "18A", expiresAt: secondExpiry),
            .init(keyword: "Locker", value: "B17", expiresAt: now.addingTimeInterval(600)),
            .init(keyword: "Room", value: "412"),
        ])

        let timeline = snapshot.displayTimeline(startingAt: now, capacity: 2)
        #expect(timeline.frames.map(\.date) == [now, firstExpiry, secondExpiry])
        #expect(timeline.frames.map { $0.records.map(\.value) } == [
            ["C24", "18A"], ["18A", "412"], ["412"],
        ])
        #expect(timeline.refreshAt == nil)
    }

    @Test("Long expiry chains renew the timeline while a valid entry is still visible")
    func renewsLongTimeline() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let snapshot = StackWidgetSnapshot(records: (1...30).map { index in
            .init(keyword: "Room", value: String(index), expiresAt: now.addingTimeInterval(Double(index * 600)))
        })

        let timeline = snapshot.displayTimeline(startingAt: now, capacity: 1)
        #expect(timeline.frames.first?.records.first?.value == "1")
        #expect(timeline.frames.last?.records.first?.value == "24")
        #expect(timeline.refreshAt == timeline.frames.last?.date)
    }
}
