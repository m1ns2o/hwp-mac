import AppKit

extension NSColor {
    convenience init(cssHex: String, alpha: CGFloat = 1.0) {
        let normalized = cssHex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            self.init(calibratedWhite: 0, alpha: alpha)
            return
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
