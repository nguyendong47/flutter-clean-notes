import SwiftUI
import WidgetKit

// MARK: - Aurora Theme & Design Tokens
enum AuroraWidgetTheme {
    static let indigo = Color(red: 0x67 / 255.0, green: 0x57 / 255.0, blue: 0xD9 / 255.0)
    static let darkIndigo = Color(red: 0xA9 / 255.0, green: 0x9B / 255.0, blue: 0xFF / 255.0)
    static let mint = Color(red: 0x2D / 255.0, green: 0xB9 / 255.0, blue: 0xA8 / 255.0)
    static let lightCanvas = Color(red: 0xF4 / 255.0, green: 0xF6 / 255.0, blue: 0xFF / 255.0)
    static let darkCanvas = Color(red: 0x0B / 255.0, green: 0x10 / 255.0, blue: 0x20 / 255.0)
    static let lightText = Color(red: 0x17 / 255.0, green: 0x20 / 255.0, blue: 0x3B / 255.0)
    static let darkGlassBackground = Color(red: 0x15 / 255.0, green: 0x17 / 255.0, blue: 0x2B / 255.0).opacity(0.92)
    static let lightGlassBackground = Color(red: 0xF8 / 255.0, green: 0xF9 / 255.0, blue: 0xFD / 255.0)
}

extension Color {
    init(argb: Int) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a > 0 ? a : 1.0)
    }
}

extension View {
    @ViewBuilder
    func applyWidgetBackground<B: View>(_ backgroundView: B) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            self.background(backgroundView)
        }
    }
}

extension WidgetConfiguration {
    func disableContentMarginsIfNeeded() -> some WidgetConfiguration {
        if #available(iOS 17.0, *) {
            return self.contentMarginsDisabled()
        } else {
            return self
        }
    }
}
