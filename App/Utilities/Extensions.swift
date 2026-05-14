import AppKit
import SwiftUI

extension NSColor {
    convenience init?(hex: String, alpha: CGFloat = 1.0) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }

        guard hexString.count == 6,
              let hexValue = Int(hexString, radix: 16) else { return nil }

        let r = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hexValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    init(hex: String, alpha: CGFloat = 1.0) {
        if let nsColor = NSColor(hex: hex, alpha: alpha) {
            self.init(nsColor)
        } else {
            self.init(red: 0.5, green: 0.5, blue: 0.5, opacity: alpha)
        }
    }
}
