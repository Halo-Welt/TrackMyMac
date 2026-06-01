import SwiftUI
import Carbon
import AppKit

/// Mac-style keyboard with per-key heatmap overlay.
///
/// Layout:
///   1. Outer bezel: rounded dark grey rectangle simulating the unibody chassis.
///   2. Each key: rounded rectangle, dark face + light glyph, system-dependent
///      gradient and stroke for that "Magic Keyboard" feel.
///   3. Overlay: a colored fill whose intensity is keyed off the press count.
struct KeyboardHeatmap: View {
    let counts: [Int: Int]
    let maxCount: Int

    var body: some View {
        GeometryReader { geo in
            // 15 grid units across; matches widest row (number row).
            let cols: CGFloat = 15
            let bezelPadding: CGFloat = 12
            let unit = (geo.size.width - bezelPadding * 2 - 14 * 4) / cols

            ZStack {
                // Bezel
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.10)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

                VStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { rowIdx in
                        HStack(spacing: 4) {
                            ForEach(rows[rowIdx].indices, id: \.self) { i in
                                let key = rows[rowIdx][i]
                                keyView(key, unit: unit)
                            }
                        }
                    }
                }
                .padding(bezelPadding)
            }
        }
    }

    @ViewBuilder
    private func keyView(_ key: Key, unit: CGFloat) -> some View {
        let n = key.code.flatMap { counts[$0] } ?? 0
        let ratio = maxCount > 0 ? min(Double(n) / Double(maxCount), 1.0) : 0
        let isTracked = key.code != nil

        let keyHeight: CGFloat = key.isFunctionRow ? 28 : 40
        let cornerRadius: CGFloat = 5
        let baseFill = LinearGradient(
            colors: [
                Color(white: 0.30),
                Color(white: 0.22)
            ],
            startPoint: .top, endPoint: .bottom
        )

        ZStack {
            // Key cap
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(baseFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.black.opacity(0.55), lineWidth: 0.8)
                )
                .overlay(
                    // Inner highlight (top edge)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), .clear],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.plusLighter)
                )
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)

            // Heatmap overlay (only for tracked keys with data)
            if isTracked && ratio > 0 {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Self.color(for: ratio).opacity(0.78))
                    .padding(1)
            }

            // Glyph
            keyGlyph(key, ratio: ratio)
        }
        .frame(width: unit * key.span - 4, height: keyHeight)
    }

    @ViewBuilder
    private func keyGlyph(_ key: Key, ratio: Double) -> some View {
        let glyphColor: Color = ratio > 0.55 ? .white : Color(white: 0.92)
        let n = key.code.flatMap { counts[$0] } ?? 0

        if key.label.count > 4 || key.span >= 2.0 {
            // Long key: align label top-left, count bottom-right
            VStack(alignment: .leading) {
                HStack {
                    Text(key.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(glyphColor)
                    Spacer()
                }
                Spacer()
                if n > 0 {
                    HStack {
                        Spacer()
                        Text("\(n)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(glyphColor.opacity(0.95))
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        } else {
            // Standard key: glyph centered
            VStack(spacing: 2) {
                Text(key.label)
                    .font(.system(size: key.label.count == 1 ? 13 : 11, weight: .semibold))
                    .foregroundStyle(glyphColor)
                if n > 0 {
                    Text("\(n)")
                        .font(.system(size: 8))
                        .foregroundStyle(glyphColor.opacity(0.75))
                }
            }
        }
    }

    /// Heatmap color ramp.
    static func color(for ratio: Double) -> Color {
        if ratio <= 0 { return Color.gray.opacity(0.0) }
        let stops: [(Double, Color)] = [
            (0.00, Color(red: 0.20, green: 0.45, blue: 0.95)),
            (0.25, Color(red: 0.20, green: 0.70, blue: 0.95)),
            (0.50, Color(red: 0.10, green: 0.75, blue: 0.45)),
            (0.75, Color(red: 0.95, green: 0.70, blue: 0.20)),
            (1.00, Color(red: 0.95, green: 0.30, blue: 0.30))
        ]
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
                     opacity: 1.0)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> Double {
        Double(a) + (Double(b) - Double(a)) * t
    }
}

private struct Key {
    let label: String
    let code: Int?
    let span: CGFloat
    let isFunctionRow: Bool

    init(_ label: String, _ code: Int?, _ span: CGFloat = 1, function: Bool = false) {
        self.label = label
        self.code = code
        self.span = span
        self.isFunctionRow = function
    }
}

private let rows: [[Key]] = [
    // Row 1 — function row (esc + F1..F12 + power)
    [
        Key("esc", kVK_Escape, 1.25, function: true),
        Key("F1", kVK_F1, 1, function: true),
        Key("F2", kVK_F2, 1, function: true),
        Key("F3", kVK_F3, 1, function: true),
        Key("F4", kVK_F4, 1, function: true),
        Key("F5", kVK_F5, 1, function: true),
        Key("F6", kVK_F6, 1, function: true),
        Key("F7", kVK_F7, 1, function: true),
        Key("F8", kVK_F8, 1, function: true),
        Key("F9", kVK_F9, 1, function: true),
        Key("F10", kVK_F10, 1, function: true),
        Key("F11", kVK_F11, 1, function: true),
        Key("F12", kVK_F12, 1, function: true),
        Key("⏻", nil, 1.25, function: true)
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
    // Row 4 — Home row
    [
        Key("⇪", kVK_CapsLock, 1.75),
        Key("A", kVK_ANSI_A), Key("S", kVK_ANSI_S), Key("D", kVK_ANSI_D),
        Key("F", kVK_ANSI_F), Key("G", kVK_ANSI_G), Key("H", kVK_ANSI_H),
        Key("J", kVK_ANSI_J), Key("K", kVK_ANSI_K), Key("L", kVK_ANSI_L),
        Key(";", kVK_ANSI_Semicolon), Key("'", kVK_ANSI_Quote),
        Key("return", kVK_Return, 2.25)
    ],
    // Row 5 — Z row
    [
        Key("shift", kVK_Shift, 2.25),
        Key("Z", kVK_ANSI_Z), Key("X", kVK_ANSI_X), Key("C", kVK_ANSI_C),
        Key("V", kVK_ANSI_V), Key("B", kVK_ANSI_B), Key("N", kVK_ANSI_N),
        Key("M", kVK_ANSI_M),
        Key(",", kVK_ANSI_Comma), Key(".", kVK_ANSI_Period), Key("/", kVK_ANSI_Slash),
        Key("shift", kVK_RightShift, 2.75)
    ],
    // Row 6 — bottom (modifiers + space + arrows)
    [
        Key("fn", kVK_Function, 1.0),
        Key("⌃", kVK_Control, 1.0),
        Key("⌥", kVK_Option, 1.0),
        Key("⌘", kVK_Command, 1.25),
        Key("space", kVK_Space, 5.5),
        Key("⌘", kVK_RightCommand, 1.25),
        Key("⌥", kVK_RightOption, 1.0),
        Key("←", kVK_LeftArrow, 1.0),
        Key("↓", kVK_DownArrow, 1.0),
        Key("↑", kVK_UpArrow, 1.0),
        Key("→", kVK_RightArrow, 1.0)
    ]
]
