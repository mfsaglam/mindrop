import AVFoundation
import MindropCore
import SwiftUI
import Vision
import VisionKit

/// The camera, with Live Text: the text and QR codes it sees are outlined, and tapping one
/// hands it back as the value. Only the value: the keyword is always the user's own word.
///
/// A Wi-Fi QR code comes back as "Network: … / Password: …", which the detail screen reads
/// as a network and draws as a QR code again.
struct ValueScanner: View {
    let scanned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    /// Whether this iPhone can scan at all. DataScanner needs a Neural Engine and a camera,
    /// which the simulator does not have, so the button is not offered there.
    static var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .authorized:
                    LiveTextScanner { text in
                        scanned(text)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("Tap the text or QR code to save")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.bottom, 24)
                    }
                case .notDetermined:
                    Color.clear
                        .task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            access = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                default:
                    ContentUnavailableView {
                        Label("Camera Access Is Off", image: "ix.scan.linear")
                    } description: {
                        Text("Mindrop uses the camera to scan text and QR codes. You can allow it in Settings.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// VisionKit's scanner, outlining text and QR codes and reporting the one tapped.
private struct LiveTextScanner: UIViewControllerRepresentable {
    let tapped: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(), .barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        // Starting before the scanner is on screen leaves the camera dark.
        Task { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.tapped = tapped
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(tapped: tapped) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var tapped: (String) -> Void

        init(tapped: @escaping (String) -> Void) {
            self.tapped = tapped
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            let text: String? = switch item {
            case .text(let text):
                text.transcript
            case .barcode(let code):
                code.payloadStringValue.map { WiFiCredentials(qrPayload: $0)?.memoryValue ?? $0 }
            @unknown default:
                nil
            }
            let value = MemoryNormalizer.normalizeValue(text ?? "")
            guard !value.isEmpty else { return }
            tapped(value)
        }
    }
}
