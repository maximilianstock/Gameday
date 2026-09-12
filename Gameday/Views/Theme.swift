import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Visual language: flat surfaces, hairline dividers, restrained greys, one accent, one alert colour.
enum Theme {
    static let width: CGFloat = 384
    static let maxListHeight: CGFloat = 560
    static let minListHeight: CGFloat = 120
    static let emptyStateHeight: CGFloat = 200
    static let cornerRadius: CGFloat = 6

    static let background = Color(nsColor: .adaptive(light: .white, dark: NSColor(hex: 0x1E1E1E)))
    static let textPrimary = Color(nsColor: .adaptive(light: NSColor(hex: 0x37352F), dark: NSColor(hex: 0xD4D4D4)))
    static let textSecondary = Color(nsColor: .adaptive(light: NSColor(hex: 0x787774), dark: NSColor(hex: 0x9B9B9B)))
    static let textTertiary = Color(nsColor: .adaptive(light: NSColor(hex: 0x9B9A97), dark: NSColor(hex: 0x737373)))
    static let divider = Color(nsColor: .adaptive(light: NSColor(hex: 0x37352F, alpha: 0.09), dark: NSColor(hex: 0xFFFFFF, alpha: 0.094)))
    static let hover = Color(nsColor: .adaptive(light: NSColor(hex: 0x37352F, alpha: 0.08), dark: NSColor(hex: 0xFFFFFF, alpha: 0.055)))
    static let pressed = Color(nsColor: .adaptive(light: NSColor(hex: 0x37352F, alpha: 0.16), dark: NSColor(hex: 0xFFFFFF, alpha: 0.1)))
    static let placeholder = Color(nsColor: .adaptive(light: NSColor(hex: 0x37352F, alpha: 0.06), dark: NSColor(hex: 0xFFFFFF, alpha: 0.06)))
    static let accent = Color(nsColor: .adaptive(light: NSColor(hex: 0x2383E2), dark: NSColor(hex: 0x529CCA)))
    static let live = Color(nsColor: .adaptive(light: NSColor(hex: 0xE03E3E), dark: NSColor(hex: 0xEB5757)))

    enum Fonts {
        static let body = Font.system(size: 13)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let title = Font.system(size: 13, weight: .semibold)
        static let score = Font.system(size: 13, weight: .semibold).monospacedDigit()
        static let setScore = Font.system(size: 12.5, weight: .medium).monospacedDigit()
        static let sectionHeader = Font.system(size: 11, weight: .semibold)
        static let status = Font.system(size: 11.5, weight: .medium).monospacedDigit()
        static let caption = Font.system(size: 11)
        static let captionMedium = Font.system(size: 11, weight: .medium)
    }
}

// MARK: - Environment

private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering offline snapshots; scroll views then lay out at full height.
    var isSnapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}
