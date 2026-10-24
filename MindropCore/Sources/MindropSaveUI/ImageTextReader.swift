#if os(iOS)
import ImageIO
import MindropCore
import Vision

/// Reads the text and QR codes in a shared image, on the device.
public enum ImageTextReader {
    /// Large enough for small print in a screenshot, small enough to stay well inside
    /// an extension's memory limit even for a 48-megapixel photo.
    private static let longestSide = 3000

    public static func lines(in data: Data) async -> [String] {
        guard let image = downsampled(data) else { return [] }

        var text = RecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.automaticallyDetectsLanguage = true
        var codes = DetectBarcodesRequest()
        codes.symbologies = [.qr]

        // Run apart, so one failing (the barcode detector is unavailable on some
        // hardware, the simulator included) doesn't lose what the other found.
        let handler = ImageRequestHandler(image)
        let lines = (try? await handler.perform(text)) ?? []
        let barcodes = (try? await handler.perform(codes)) ?? []
        return ImageText.lines(
            recognized: lines.map(\.transcript),
            codes: barcodes.compactMap(\.payloadString)
        )
    }

    /// Decodes the image already turned upright and scaled down, so a photo's
    /// orientation is applied and the full-size bitmap is never held in memory.
    private static func downsampled(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
#endif
