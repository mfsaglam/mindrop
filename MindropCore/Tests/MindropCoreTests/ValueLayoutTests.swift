import Testing
@testable import MindropCore

@Suite("Showing a whole value")
struct ValueLayoutTests {
    @Test("A card number is grouped in fours, however it was typed")
    func cardNumber() {
        #expect(ValueLayout(value: "4111111111111111") == .groups(["4111", "1111", "1111", "1111"]))
        #expect(ValueLayout(value: "4111-1111-1111-1111") == .groups(["4111", "1111", "1111", "1111"]))
    }

    @Test("A number that fails the Luhn check, or has more after it, is left as typed")
    func notACardNumber() {
        #expect(ValueLayout(value: "4111111111111112") == .text)
        #expect(ValueLayout(value: "4111 1111 1111 1111 12/28 123") == .text)
        #expect(ValueLayout(value: "123-45-6789") == .text)
    }

    @Test("An IBAN is grouped in fours and upper-cased; a near miss is not")
    func iban() {
        #expect(ValueLayout(value: "TR330006100519786457841326") == .groups([
            "TR33", "0006", "1005", "1978", "6457", "8413", "26",
        ]))
        #expect(ValueLayout(value: "gb82 west 1234 5698 7654 32") == .groups([
            "GB82", "WEST", "1234", "5698", "7654", "32",
        ]))
        #expect(ValueLayout(value: "TR330006100519786457841327") == .text)
    }

    @Test("A recovery phrase is split into numbered words")
    func recoveryPhrase() {
        let phrase = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        #expect(ValueLayout(value: phrase) == .words(phrase.split(separator: " ").map(String.init)))
        #expect(ValueLayout(value: "the quick brown fox") == .text)
        #expect(ValueLayout(value: "Bağdat Cd. 123, Kadıköy, İstanbul") == .text)
    }

    @Test("A labelled Wi-Fi value gives a payload a camera can join")
    func wifiWithNetwork() throws {
        let credentials = try #require(WiFiCredentials(value: "Network: Home 5G\nPassword: Super;Fast"))
        #expect(credentials.networkName == "Home 5G")
        #expect(credentials.password == "Super;Fast")
        #expect(credentials.qrPayload == #"WIFI:T:WPA;S:Home 5G;P:Super\;Fast;;"#)

        let turkish = try #require(WiFiCredentials(value: "ağ adı: Ev / şifre: kedi1234"))
        #expect(turkish.networkName == "Ev")
        #expect(turkish.password == "kedi1234")
    }

    @Test("A bare password gives a payload of just the password")
    func wifiPasswordOnly() throws {
        let credentials = try #require(WiFiCredentials(value: "SuperFast2026!"))
        #expect(credentials.networkName == nil)
        #expect(credentials.qrPayload == "SuperFast2026!")
    }

    @Test("Prose with no labels is not taken for a password")
    func wifiProse() {
        #expect(WiFiCredentials(value: "ask the front desk") == nil)
    }

    @Test("A scanned Wi-Fi QR code becomes a value that reads back as the same network")
    func wifiFromQRCode() throws {
        let credentials = try #require(WiFiCredentials(qrPayload: #"WIFI:T:WPA;S:Home 5G;P:Super\;Fast;H:false;;"#))
        #expect(credentials.networkName == "Home 5G")
        #expect(credentials.password == "Super;Fast")
        #expect(credentials.memoryValue == "Network: Home 5G\nPassword: Super;Fast")
        #expect(WiFiCredentials(value: credentials.memoryValue) == credentials)
        #expect(WiFiCredentials(qrPayload: credentials.qrPayload) == credentials)
    }

    @Test("Other QR codes and open networks are not read as Wi-Fi")
    func wifiFromOtherQRCodes() {
        #expect(WiFiCredentials(qrPayload: "https://example.com") == nil)
        #expect(WiFiCredentials(qrPayload: "WIFI:T:nopass;S:Cafe;;") == nil)
    }
}
