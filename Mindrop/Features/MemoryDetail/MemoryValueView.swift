import CoreImage.CIFilterBuiltins
import MindropCore
import SwiftUI

/// The value on the detail screen, laid out to be read: card numbers and IBANs in blocks of
/// four, recovery phrases as numbered words, anything else as typed, in the typeface its
/// category calls for. Display only — what is copied is always the value exactly as saved.
struct MemoryValueView: View {
    let value: String
    let category: MemoryCategory?
    /// Words to mark, from the search that found this memory in Spotlight.
    var highlight: String?

    var body: some View {
        switch ValueLayout(value: value) {
        case .text:
            // User content, shown verbatim, never looked up.
            HighlightedText(value, query: highlight)
                .font(ValueStyle(value: value, category: category).font(for: value))
        case .groups(let groups):
            let grouped = groups.joined(separator: " ")
            HighlightedText(grouped, query: highlight)
                .font(ValueStyle.exact.font(for: grouped))
        case .words(let words):
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 10) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(index + 1, format: .number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        HighlightedText(word, query: highlight)
                            .font(.body.monospaced().weight(.medium))
                    }
                }
            }
        }
    }
}

/// The typeface a value is set in, by what kind of thing it is.
enum ValueStyle: Equatable {
    /// Read out or typed one character at a time, where 0 and O, or l, I and 1, must not
    /// be mistaken: monospaced, whose letterforms tell them apart.
    case exact
    /// Words, names, dates and addresses, read as language: the system font.
    case prose
    /// Phone numbers: the system font with digits of equal width, so they read in blocks.
    case phone
    /// Web addresses, long and rarely read in full: smaller, so they wrap less.
    case link

    init(value: String, category: MemoryCategory?) {
        switch category {
        case .code, .finance, .account, .network, .document, .vehicle:
            self = .exact
        case .contact:
            self = .phone
        case .link:
            self = .link
        case .people, .address:
            self = .prose
        case .health, .home, .other, nil:
            // Categories that hold both: a blood type is prose, an insurance number or an
            // alarm code is not. One word with a digit in it is taken for a code.
            let isCode = !value.contains(where: \.isWhitespace) && value.contains(where: \.isNumber)
            self = isCode ? .exact : .prose
        }
    }

    /// Large while the value is short, smaller as it grows, so most values fit on a line
    /// or two. Monospaced characters are wider, so they step down sooner.
    func font(for value: String) -> Font {
        let length = value.count
        switch self {
        case .exact:
            let style: Font.TextStyle = length <= 16 ? .largeTitle : length <= 40 ? .title : .title2
            return .system(style, design: .monospaced, weight: .semibold)
        case .prose:
            return (length <= 40 ? Font.largeTitle : .title).weight(.bold)
        case .phone:
            return Font.largeTitle.weight(.bold).monospacedDigit()
        case .link:
            return Font.title2.weight(.semibold)
        }
    }
}

/// A QR code for a Wi-Fi memory, for showing a guest the screen. It joins the network when
/// the value names it, and otherwise carries just the password, which a camera offers to
/// copy. Made on the device by Core Image; nothing is sent anywhere.
struct WiFiQRCodeView: View {
    let credentials: WiFiCredentials

    var body: some View {
        HStack(spacing: 16) {
            if let image = Self.image(for: credentials.qrPayload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 132, height: 132)
                    // A quiet border of white, which scanners need, in dark mode too.
                    .padding(10)
                    .background(.white, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
            }
            Group {
                if let networkName = credentials.networkName {
                    Text("Scan to join “\(networkName)”")
                } else {
                    Text("Scan to copy the password")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private static func image(for payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: image)
    }
}
