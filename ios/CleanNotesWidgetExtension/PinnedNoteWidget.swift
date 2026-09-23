import SwiftUI
import WidgetKit

// MARK: - Models
struct ChecklistItem: Codable {
    let text: String
    let done: Bool
}

struct PinnedNoteEntry: TimelineEntry {
    let date: Date
    let hasPinned: Bool
    let noteId: String
    let title: String
    let content: String
    let checklist: [ChecklistItem]
    let colorValue: Int
    let updatedAt: String

    static var empty: PinnedNoteEntry {
        PinnedNoteEntry(
            date: Date(),
            hasPinned: false,
            noteId: "",
            title: "",
            content: "",
            checklist: [],
            colorValue: 0,
            updatedAt: ""
        )
    }

    static var placeholder: PinnedNoteEntry {
        PinnedNoteEntry(
            date: Date(),
            hasPinned: true,
            noteId: "1",
            title: "Ghi chú mẫu",
            content: "Nội dung ghi chú của bạn...",
            checklist: [
                ChecklistItem(text: "Việc cần làm 1", done: false),
                ChecklistItem(text: "Việc đã hoàn thành", done: true)
            ],
            colorValue: 0xFF6757D9,
            updatedAt: ""
        )
    }
}

// MARK: - Timeline Provider
struct PinnedNoteProvider: TimelineProvider {
    private let appGroupId = "group.com.cleannotes.app"

    func placeholder(in context: Context) -> PinnedNoteEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedNoteEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedNoteEntry>) -> Void) {
        let entry = loadEntry()
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }

    private func loadEntry() -> PinnedNoteEntry {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            return .empty
        }

        let hasPinned = userDefaults.bool(forKey: "widget_has_pinned")
        let noteId = userDefaults.string(forKey: "widget_pinned_id") ?? ""
        let title = userDefaults.string(forKey: "widget_pinned_title") ?? ""
        let content = userDefaults.string(forKey: "widget_pinned_content") ?? ""
        let checklistJson = userDefaults.string(forKey: "widget_pinned_checklist") ?? "[]"
        let colorValue = userDefaults.integer(forKey: "widget_pinned_color")
        let updatedAt = userDefaults.string(forKey: "widget_pinned_updated_at") ?? ""

        var checklist: [ChecklistItem] = []
        if let data = checklistJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
            checklist = decoded
        }

        return PinnedNoteEntry(
            date: Date(),
            hasPinned: hasPinned,
            noteId: noteId,
            title: title,
            content: content,
            checklist: checklist,
            colorValue: colorValue,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Widget View
struct PinnedNoteWidgetView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetFamily) var family
    let entry: PinnedNoteEntry

    private var primaryColor: Color {
        colorScheme == .dark ? AuroraWidgetTheme.darkIndigo : AuroraWidgetTheme.indigo
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white : AuroraWidgetTheme.lightText
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.70) : AuroraWidgetTheme.lightText.opacity(0.65)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? AuroraWidgetTheme.darkGlassBackground : AuroraWidgetTheme.lightGlassBackground
    }

    private var pillBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : AuroraWidgetTheme.indigo.opacity(0.1)
    }

    private var pillBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : AuroraWidgetTheme.indigo.opacity(0.2)
    }

    private var maxChecklistItems: Int {
        switch family {
        case .systemSmall:
            return 3
        case .systemMedium:
            return 4
        case .systemLarge:
            return 8
        default:
            return 4
        }
    }

    var body: some View {
        Group {
            if entry.hasPinned {
                activeLayout
            } else {
                emptyLayout
            }
        }
        .applyWidgetBackground(cardBackground)
    }

    private var emptyLayout: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "pin.fill")
                .font(.system(size: 26))
                .foregroundColor(primaryColor.opacity(0.45))

            Text("Chưa có ghi chú được ghim")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)

            Text("Mở Clean Notes để ghim ghi chú quan trọng!")
                .font(.system(size: 11))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))
                Text("Ghi chú")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(colorScheme == .dark ? .white : primaryColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(pillBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(pillBorder, lineWidth: 1)
            )
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetURL(URL(string: "clean-notes://new?homeWidget=true")!)
    }

    private var activeLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                if entry.colorValue != 0 {
                    Circle()
                        .fill(Color(argb: entry.colorValue))
                        .frame(width: 8, height: 8)
                }
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundColor(primaryColor)

                Text(entry.title.isEmpty ? "Ghi chú đã ghim" : entry.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(textColor)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundColor(secondaryTextColor)
            }

            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                .frame(height: 1)

            // Body
            if !entry.checklist.isEmpty {
                checklistContent
            } else {
                textContent
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetURL(URL(string: entry.noteId.isEmpty ? "clean-notes://new?homeWidget=true" : "clean-notes://note?id=\(entry.noteId)&homeWidget=true")!)
    }

    private var checklistContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let items = Array(entry.checklist.prefix(maxChecklistItems))
            ForEach(0..<items.count, id: \.self) { idx in
                let item = items[idx]
                HStack(spacing: 6) {
                    Image(systemName: item.done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(item.done ? AuroraWidgetTheme.mint : secondaryTextColor)
                    Text(item.text)
                        .font(.system(size: 12))
                        .foregroundColor(item.done ? secondaryTextColor : textColor)
                        .strikethrough(item.done, color: secondaryTextColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            if entry.checklist.count > maxChecklistItems {
                Text("+ \(entry.checklist.count - maxChecklistItems) mục khác...")
                    .font(.system(size: 11))
                    .foregroundColor(secondaryTextColor)
                    .padding(.leading, 18)
            }
        }
    }

    private var textContent: some View {
        Text(entry.content.isEmpty ? "Không có nội dung" : entry.content)
            .font(.system(size: 12))
            .foregroundColor(secondaryTextColor)
            .lineSpacing(3)
            .lineLimit(family == .systemSmall ? 4 : (family == .systemMedium ? 5 : 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget Declaration
struct PinnedNoteWidget: Widget {
    let kind: String = "PinnedNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedNoteProvider()) { entry in
            PinnedNoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Clean Notes - Ghi chú ghim")
        .description("Hiển thị ghi chú đã ghim hoặc danh sách việc cần làm.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .disableContentMarginsIfNeeded()
    }
}
