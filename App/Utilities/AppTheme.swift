import SwiftUI
import AppKit

enum MusicEDLColorKey: String, CaseIterable, Identifiable {
    case backgroundTop
    case backgroundBottom
    case card
    case cardElevated
    case toolbar
    case summary
    case footer
    case tableRowA
    case tableRowB
    case fieldBackground
    case border
    case softBorder
    case glassHighlight
    case textPrimary
    case textSecondary
    case textMuted
    case accent
    case success
    case warning
    case danger
    case buttonLoad
    case buttonMarkers
    case buttonDelete
    case buttonMerge
    case buttonExport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backgroundTop: return "Background Top"
        case .backgroundBottom: return "Background Bottom"
        case .card: return "Card"
        case .cardElevated: return "Card Elevated"
        case .toolbar: return "Toolbar"
        case .summary: return "Summary"
        case .footer: return "Footer"
        case .tableRowA: return "Table Row A"
        case .tableRowB: return "Table Row B"
        case .fieldBackground: return "Field Background"
        case .border: return "Border"
        case .softBorder: return "Soft Border"
        case .glassHighlight: return "Glass Highlight"
        case .textPrimary: return "Text Primary"
        case .textSecondary: return "Text Secondary"
        case .textMuted: return "Text Muted"
        case .accent: return "Accent"
        case .success: return "Success"
        case .warning: return "Warning"
        case .danger: return "Danger"
        case .buttonLoad: return "Button Load"
        case .buttonMarkers: return "Button Markers"
        case .buttonDelete: return "Button Delete"
        case .buttonMerge: return "Button Merge"
        case .buttonExport: return "Button XLSX"
        }
    }

    var defaultHex: String {
        switch self {
        case .backgroundTop: return "#2D3359"
        case .backgroundBottom: return "#212640"
        case .card: return "#0D1422"
        case .cardElevated: return "#162033"
        case .toolbar: return "#162033"
        case .summary: return "#0D1422"
        case .footer: return "#0D1422"
        case .tableRowA: return "#101827"
        case .tableRowB: return "#172235"
        case .fieldBackground: return "#162033"
        case .border: return "#FFFFFF"
        case .softBorder: return "#FFFFFF"
        case .glassHighlight: return "#FFFFFF"
        case .textPrimary: return "#FFFFFF"
        case .textSecondary: return "#D8CAD8"
        case .textMuted: return "#D8CAD8"
        case .accent: return "#27A9FF"
        case .success: return "#20EFA3"
        case .warning: return "#FFE347"
        case .danger: return "#FF3366"
        case .buttonLoad: return "#FFE347"
        case .buttonMarkers: return "#FF4FD8"
        case .buttonDelete: return "#FF3366"
        case .buttonMerge: return "#20EFA3"
        case .buttonExport: return "#27A9FF"
        }
    }

    var defaultOpacity: Double {
        switch self {
        case .toolbar: return 0.92
        case .summary: return 0.88
        case .footer: return 0.9
        case .tableRowA: return 0.58
        case .tableRowB: return 0.52
        case .fieldBackground: return 0.9
        case .border: return 0.34
        case .softBorder: return 0.16
        case .glassHighlight: return 0.18
        case .textPrimary: return 0.96
        case .textSecondary: return 0.84
        case .textMuted: return 0.62
        default: return 1
        }
    }
}

final class MusicEDLColorTheme: ObservableObject {
    static let shared = MusicEDLColorTheme()

    @Published private(set) var refreshToken = UUID()

    private let userDefaultsKey = "gogolabs.music-edl.colorTheme.v1"
    private let userDefaults: UserDefaults
    private var values: [String: String]

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.values = userDefaults.dictionary(forKey: userDefaultsKey) as? [String: String] ?? [:]
    }

    func color(for key: MusicEDLColorKey) -> Color {
        baseColor(for: key).opacity(key.defaultOpacity)
    }

    func baseColor(for key: MusicEDLColorKey) -> Color {
        Color(hex: hexString(for: key))
    }

    func binding(for key: MusicEDLColorKey) -> Binding<Color> {
        Binding(
            get: { self.baseColor(for: key) },
            set: { self.setColor($0, for: key) }
        )
    }

    func hexString(for key: MusicEDLColorKey) -> String {
        values[key.rawValue] ?? key.defaultHex
    }

    func setColor(_ color: Color, for key: MusicEDLColorKey) {
        guard let hex = NSColor(color).hexString else { return }
        values[key.rawValue] = hex
        persist()
    }

    func resetColor(for key: MusicEDLColorKey) {
        values.removeValue(forKey: key.rawValue)
        persist()
    }

    func resetDefaults() {
        values.removeAll()
        persist()
    }

    private func persist() {
        userDefaults.set(values, forKey: userDefaultsKey)
        refreshToken = UUID()
    }
}

enum AppTheme {
    private static let theme = MusicEDLColorTheme.shared

    static var backgroundTop: Color { theme.baseColor(for: .backgroundTop) }
    static var backgroundBottom: Color { theme.baseColor(for: .backgroundBottom) }
    static var background: Color { backgroundBottom }
    static var card: Color { theme.baseColor(for: .card) }
    static var cardElevated: Color { theme.baseColor(for: .cardElevated) }
    static var toolbar: Color { theme.color(for: .toolbar) }
    static var summary: Color { theme.color(for: .summary) }
    static var footer: Color { theme.color(for: .footer) }
    static var tableRowA: Color { theme.color(for: .tableRowA) }
    static var tableRowB: Color { theme.color(for: .tableRowB) }
    static var fieldBackground: Color { theme.color(for: .fieldBackground) }
    static var border: Color { theme.color(for: .border) }
    static var softBorder: Color { theme.color(for: .softBorder) }
    static var glassHighlight: Color { theme.color(for: .glassHighlight) }

    static var textPrimary: Color { theme.color(for: .textPrimary) }
    static var textSecondary: Color { theme.color(for: .textSecondary) }
    static var textMuted: Color { theme.color(for: .textMuted) }

    static var accent: Color { theme.baseColor(for: .accent) }
    static var accentSoft: Color { Color(hex: "0F5C7D") }
    static var accentWarm: Color { theme.baseColor(for: .buttonMarkers) }
    static var success: Color { theme.baseColor(for: .success) }
    static var warning: Color { theme.baseColor(for: .warning) }
    static var danger: Color { theme.baseColor(for: .danger) }

    static var buttonLoad: Color { theme.baseColor(for: .buttonLoad) }
    static var buttonMarkers: Color { theme.baseColor(for: .buttonMarkers) }
    static var buttonDelete: Color { theme.baseColor(for: .buttonDelete) }
    static var buttonMerge: Color { theme.baseColor(for: .buttonMerge) }
    static var buttonExport: Color { theme.baseColor(for: .buttonExport) }

    static let cardCornerRadius: CGFloat = 15
    static let controlCornerRadius: CGFloat = 10
    static let cardBorderWidth: CGFloat = 1.4

    static var windowGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension NSColor {
    var hexString: String? {
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
