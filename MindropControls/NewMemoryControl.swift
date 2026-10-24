import AppIntents
import MindropIntents
import SwiftUI
import WidgetKit

@main
struct MindropControls: WidgetBundle {
    var body: some Widget {
        NewMemoryControl()
        ScanValueControl()
    }
}

/// A Control Center and Lock Screen button that opens Mindrop on a blank editor.
///
/// Its icon is Mindrop's mark, the app icon's search icon and cursor, so the button says
/// whose it is; Control Center draws only symbols, so the mark is a custom symbol
/// (`Tools/RenderAppIcon.swift --symbol`).
struct NewMemoryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "mfsaglam.Mindrop.NewMemory") {
            ControlWidgetButton(action: NewMemoryIntent()) {
                Label("New Memory", image: "mindrop.mark")
            }
        }
        .displayName("New Memory")
        .description("Open Mindrop to start a new memory.")
    }
}

/// A Control Center and Lock Screen button that opens Mindrop's camera, to scan a value for
/// a new memory. The editor follows for the keyword.
struct ScanValueControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "mfsaglam.Mindrop.ScanValue") {
            ControlWidgetButton(action: ScanValueIntent()) {
                Label("Scan with Mindrop", image: "ix.scan.linear")
            }
        }
        .displayName("Scan with Mindrop")
        .description("Open Mindrop’s camera to scan text or a QR code.")
    }
}
