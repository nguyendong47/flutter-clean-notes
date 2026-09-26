import AppIntents
import Foundation
import home_widget
import WidgetKit

@available(iOS 17, *)
public struct ToggleChecklistItemIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Checklist Item"
    public static var isDiscoverable: Bool = false

    @Parameter(title: "Note ID")
    var noteId: String

    @Parameter(title: "Item Index")
    var index: Int

    public init() {
        self.noteId = ""
        self.index = 0
    }

    public init(noteId: String, index: Int) {
        self.noteId = noteId
        self.index = index
    }

    public func perform() async throws -> some IntentResult {
        let appGroup = "group.com.cleannotes.app"

        // 1. Instant optimistic update in UserDefaults & reload timeline (~5-20ms)
        var resolvedNoteId = noteId
        if let userDefaults = UserDefaults(suiteName: appGroup) {
            let pinnedId = userDefaults.string(forKey: "widget_pinned_id") ?? ""
            if resolvedNoteId.isEmpty {
                resolvedNoteId = pinnedId
            }

            var keysToUpdate: [String] = []
            if resolvedNoteId.isEmpty || resolvedNoteId == pinnedId {
                keysToUpdate.append("widget_pinned_checklist")
            }
            if !resolvedNoteId.isEmpty {
                keysToUpdate.append("widget_note_\(resolvedNoteId)_checklist")
            }

            var updated = false
            for key in keysToUpdate {
                if let jsonString = userDefaults.string(forKey: key),
                   let data = jsonString.data(using: .utf8),
                   var array = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: Any]] {
                    if index >= 0 && index < array.count {
                        var item = array[index]
                        let isDone = (item["done"] as? Bool) ?? false
                        item["done"] = !isDone
                        array[index] = item
                        if let updatedData = try? JSONSerialization.data(withJSONObject: array, options: []),
                           let updatedJson = String(data: updatedData, encoding: .utf8) {
                            userDefaults.set(updatedJson, forKey: key)
                            updated = true
                        }
                    }
                }
            }

            if updated {
                WidgetCenter.shared.reloadTimelines(ofKind: "PinnedNoteWidget")
            }
        }

        // 2. Dispatch to the Flutter background worker for durable SQLite persistence
        let urlString = "clean-notes://toggle-check?id=\(resolvedNoteId)&index=\(index)"
        if let url = URL(string: urlString) {
            await HomeWidgetBackgroundWorker.run(url: url, appGroup: appGroup)
        }

        return .result()
    }
}

@available(iOS 17, *)
@available(iOSApplicationExtension, unavailable)
extension ToggleChecklistItemIntent: ForegroundContinuableIntent {}
