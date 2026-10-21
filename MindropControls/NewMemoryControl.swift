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
struct NewMemoryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "mfsaglam.Mindrop.NewMemory") {
            ControlWidgetButton(action: NewMemoryIntent()) {
                Label("New Memory", systemImage: "plus")
            }
        }
        .displayName("New Memory")
        .description("Opens Mindrop ready to save a new memory.")
    }
}
