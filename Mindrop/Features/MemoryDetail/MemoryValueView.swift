import CoreImage.CIFilterBuiltins
import MindropCore
import SwiftUI

/// The value on the detail screen, laid out to be read: card numbers and IBANs in blocks of
/// four, recovery phrases as numbered words, anything else as typed. Display only — what
/// is copied is always the value exactly as saved.
struct MemoryValueView: View {
    let value: String

    var body: some View {
        switch ValueLayout(value: value) {
        case .text:
            // User content: a `String`, so it is shown verbatim, never looked up.
            Text(value)
                .font(.largeTitle)
                .fontWeight(.semibold)
        case .groups(let groups):
            Text(groups.joined(separator: " "))
                .font(.largeTitle.monospaced())
                .fontWeight(.semibold)
        case .words(let words):
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 10) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(index + 1, format: .number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(word)
                            .font(.body.monospaced().weight(.medium))
                    }
                }
            }
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
