import SwiftUI
import WidgetKit

@main
struct CleanNotesWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickActionsWidget()
        PinnedNoteWidget()
    }
}
