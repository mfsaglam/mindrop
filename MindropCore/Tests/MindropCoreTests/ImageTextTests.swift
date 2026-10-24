import Testing
@testable import MindropCore

@Suite("Picking details from an image")
struct ImageTextTests {
    @Test("QR codes come first, a Wi-Fi code as its network and password; blanks and repeats go")
    func lines() {
        let lines = ImageText.lines(
            recognized: ["Guest Wi-Fi", "  ", "Scan to join", "Guest Wi-Fi"],
            codes: ["WIFI:T:WPA;S:Home;P:secret;;", "https://example.com"]
        )
        #expect(lines == ["Network: Home\nPassword: secret", "https://example.com", "Guest Wi-Fi", "Scan to join"])
    }

    @Test("Picking lines adds each on its own line; picking one again takes it out")
    func toggling() {
        var details = ""
        details = ImageText.toggling("1 Main St", in: details)
        details = ImageText.toggling("Springfield", in: details)
        #expect(details == "1 Main St\nSpringfield")
        #expect(ImageText.details(details, contain: "Springfield"))

        details = ImageText.toggling("1 Main St", in: details)
        #expect(details == "Springfield")
        #expect(!ImageText.details(details, contain: "1 Main St"))
    }

    @Test("Only whole lines count as picked, and typed text around them stays")
    func wholeLines() {
        #expect(!ImageText.details("Springfield Gardens", contain: "Springfield"))
        #expect(ImageText.toggling("Springfield", in: "Door code 12\nSpringfield") == "Door code 12")
    }

    @Test("A Wi-Fi pick spans two lines and comes out as a whole")
    func multiLinePick() {
        let wifi = "Network: Home\nPassword: secret"
        let details = ImageText.toggling(wifi, in: "Upstairs")
        #expect(details == "Upstairs\n\(wifi)")
        #expect(ImageText.details(details, contain: wifi))
        #expect(ImageText.toggling(wifi, in: details) == "Upstairs")
    }
}
