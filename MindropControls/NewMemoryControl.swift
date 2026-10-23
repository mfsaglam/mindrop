import AppIntents
import MindropIntents
import SwiftUI
import WidgetKit

@main
struct MindropControls: WidgetBundle {
    var body: some Widget {
        NewMemoryControl()
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
        .description("Opens Mindrop ready to save a new memory.")
    }
}
