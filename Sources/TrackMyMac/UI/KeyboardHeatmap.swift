import SwiftUI
import Carbon

/// A simplified ANSI keyboard heatmap. Each key is colored by its press count
/// relative to the maximum.
struct KeyboardHeatmap: View {
    let counts: [Int: Int]
    let maxCount: Int

    var body: some View {
        GeometryReader { geo in
            let cols: CGFloat = 15  // grid units across (incl. backspace etc.)
            let unit = (geo.size.width - 12) / cols
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 4) {
                        ForEach(rows[rowIdx].indices, id: \.self) { i in
                            let key = rows[rowIdx][i]
                            keyView(key, unit: unit)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyView(_ key: Key, unit: CGFloat) -> some View {
        let n = key.code.flatMap { counts[$0] } ?? 0
        let ratio = maxCount > 0 ? min(Double(n) / Double(maxCount), 1.0) : 0
        let bg = key.code == nil
            ? Color.secondary.opacity(0.10)
            : Self.color(for: ratio)
        let textColor: Color = ratio > 0.5 ? .white : .primary
        let labelFont: Font = key.label.count > 2 ? .caption2 : .caption.bold()

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(bg)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
            VStack(alignment: .leading) {
                Text(key.label)
                    .font(labelFont)
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                Spacer(minLength: 0)
                if n > 0 {
                    Text("\(n)")
                        .font(.system(size: 9))
                        .foregroundStyle(textColor.opacity(0.85))
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                }
            }
        }
        .frame(width: unit * key.span - 4, height: 38)
    }

    static func color(for ratio: Double) -> Color {
        // Blue → green → yellow → red gradient based on ratio.
        if ratio <= 0 { return Color.gray.opacity(0.18) }
        let stops: [(Double, Color)] = [
            (0.00, Color(red: 0.20, green: 0.45, blue: 0.95).opacity(0.30)),
            (0.20, Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.55)),
            (0.45, Color(red: 0.10, green: 0.70, blue: 0.55).opacity(0.85)),
            (0.70, Color(red: 0.95, green: 0.70, blue: 0.20)),
            (1.00, Color(red: 0.95, green: 0.30, blue: 0.30))
        ]
        // Find segment
        for i in 0..<(stops.count - 1) {
            let (a, ca) = stops[i]
            let (b, cb) = stops[i + 1]
            if ratio >= a && ratio <= b {
                let t = (ratio - a) / max(b - a, 0.0001)
                return blend(ca, cb, t)
            }
        }
        return stops.last!.1
    }

    private static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .clear
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .clear
        return Color(red: lerp(na.redComponent, nb.redComponent, t),
                     green: lerp(na.greenComponent, nb.greenComponent, t),
                     blue: lerp(na.blueComponent, nb.blueComponent, t),
                     opacity: lerp(na.alphaComponent, nb.alphaComponent, t))
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> Double {
        Double(a) + (Double(b) - Double(a)) * t
    }
}

private struct Key {
    /// Display label.
    let label: String
    /// CGKeyCode (HIToolbox/Events.h). nil means "decorative key, not tracked".
    let code: Int?
    /// Width in grid units (1 = standard).
    let span: CGFloat

    init(_ label: String, _ code: Int?, _ span: CGFloat = 1) {
        self.label = label
        self.code = code
        self.span = span
    }
}

private let rows: [[Key]] = [
    // Row 1 — function row (esc + F1..F12)
    [
        Key("esc", kVK_Escape, 1.25),
        Key("F1", kVK_F1), Key("F2", kVK_F2), Key("F3", kVK_F3),
        Key("F4", kVK_F4), Key("F5", kVK_F5), Key("F6", kVK_F6),
        Key("F7", kVK_F7), Key("F8", kVK_F8), Key("F9", kVK_F9),
        Key("F10", kVK_F10), Key("F11", kVK_F11), Key("F12", kVK_F12),
        Key("⏻", nil, 1.25)
    ],
    // Row 2 — number row
    [
        Key("`", kVK_ANSI_Grave),
        Key("1", kVK_ANSI_1), Key("2", kVK_ANSI_2), Key("3", kVK_ANSI_3),
        Key("4", kVK_ANSI_4), Key("5", kVK_ANSI_5), Key("6", kVK_ANSI_6),
        Key("7", kVK_ANSI_7), Key("8", kVK_ANSI_8), Key("9", kVK_ANSI_9),
        Key("0", kVK_ANSI_0),
        Key("-", kVK_ANSI_Minus), Key("=", kVK_ANSI_Equal),
        Key("⌫", kVK_Delete, 1.5)
    ],
    // Row 3 — QWERTY
    [
        Key("⇥", kVK_Tab, 1.5),
        Key("Q", kVK_ANSI_Q), Key("W", kVK_ANSI_W), Key("E", kVK_ANSI_E),
        Key("R", kVK_ANSI_R), Key("T", kVK_ANSI_T), Key("Y", kVK_ANSI_Y),
        Key("U", kVK_ANSI_U), Key("I", kVK_ANSI_I), Key("O", kVK_ANSI_O),
        Key("P", kVK_ANSI_P),
        Key("[", kVK_ANSI_LeftBracket), Key("]", kVK_ANSI_RightBracket),
        Key("\\", kVK_ANSI_Backslash)
    ],
    // Row 4 — ASDF
    [
        Key("⇪", kVK_CapsLock, 1.75),
        Key("A", kVK_ANSI_A), Key("S", kVK_ANSI_S), Key("D", kVK_ANSI_D),
        Key("F", kVK_ANSI_F), Key("G", kVK_ANSI_G), Key("H", kVK_ANSI_H),
        Key("J", kVK_ANSI_J), Key("K", kVK_ANSI_K), Key("L", kVK_ANSI_L),
        Key(";", kVK_ANSI_Semicolon), Key("'", kVK_ANSI_Quote),
        Key("↩", kVK_Return, 2.25)
    ],
    // Row 5 — ZXCV
    [
        Key("⇧", kVK_Shift, 2.25),
        Key("Z", kVK_ANSI_Z), Key("X", kVK_ANSI_X), Key("C", kVK_ANSI_C),
        Key("V", kVK_ANSI_V), Key("B", kVK_ANSI_B), Key("N", kVK_ANSI_N),
        Key("M", kVK_ANSI_M),
        Key(",", kVK_ANSI_Comma), Key(".", kVK_ANSI_Period), Key("/", kVK_ANSI_Slash),
        Key("⇧", kVK_RightShift, 2.75)
    ],
    // Row 6 — bottom
    [
        Key("fn", kVK_Function, 1.0),
        Key("⌃", kVK_Control, 1.0),
        Key("⌥", kVK_Option, 1.0),
        Key("⌘", kVK_Command, 1.25),
        Key("Space", kVK_Space, 5.5),
        Key("⌘", kVK_RightCommand, 1.25),
        Key("⌥", kVK_RightOption, 1.0),
        Key("←", kVK_LeftArrow, 1.0),
        Key("↓", kVK_DownArrow, 1.0),
        Key("↑", kVK_UpArrow, 1.0),
        Key("→", kVK_RightArrow, 1.0)
    ]
]
