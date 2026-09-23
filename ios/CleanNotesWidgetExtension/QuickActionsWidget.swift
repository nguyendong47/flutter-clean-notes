import SwiftUI
import WidgetKit

// MARK: - Timeline Entry & Provider
struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        let entry = QuickActionsEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Widget View
struct QuickActionsWidgetView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.widgetFamily) var family
    let entry: QuickActionsEntry

    private var primaryColor: Color {
        colorScheme == .dark ? AuroraWidgetTheme.darkIndigo : AuroraWidgetTheme.indigo
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white : AuroraWidgetTheme.lightText
    }

    private var pillBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.9)
    }

    private var pillBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : AuroraWidgetTheme.indigo.opacity(0.2)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? AuroraWidgetTheme.darkGlassBackground : AuroraWidgetTheme.lightGlassBackground
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            default:
                mediumLayout
            }
        }
        .applyWidgetBackground(cardBackground)
    }

    private var mediumLayout: some View {
        HStack(spacing: 8) {
            actionPill(
                title: "Ghi chú",
                icon: "square.and.pencil",
                url: "clean-notes://new"
            )
            actionPill(
                title: "Checklist",
                icon: "checklist",
                url: "clean-notes://new?template=checklist"
            )
            actionPill(
                title: "Tìm kiếm",
                icon: "magnifyingglass",
                url: "clean-notes://search"
            )
            actionPill(
                title: "Đã ghim",
                icon: "pin.fill",
                url: "clean-notes://pinned"
            )
        }
        .padding(10)
    }

    private var smallLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionPill(title: "Ghi chú", icon: "square.and.pencil", url: "clean-notes://new")
                actionPill(title: "Checklist", icon: "checklist", url: "clean-notes://new?template=checklist")
            }
            HStack(spacing: 8) {
                actionPill(title: "Tìm kiếm", icon: "magnifyingglass", url: "clean-notes://search")
                actionPill(title: "Đã ghim", icon: "pin.fill", url: "clean-notes://pinned")
            }
        }
        .padding(10)
        .widgetURL(URL(string: "clean-notes://new")!)
    }

    @ViewBuilder
    private func actionPill(title: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(primaryColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(primaryColor)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(pillBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(pillBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Widget Declaration
struct QuickActionsWidget: Widget {
    let kind: String = "QuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            QuickActionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Clean Notes - Phím tắt")
        .description("Tạo ghi chú nhanh và tìm kiếm ngay từ màn hình chính.")
        .supportedFamilies([.systemMedium, .systemSmall])
        .disableContentMarginsIfNeeded()
    }
}
