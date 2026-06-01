import Foundation
import Carbon
import CoreGraphics

/// Maps a CGKeyCode to a human-readable label, e.g. 0 -> "A", 49 -> "Space".
enum KeyName {
    /// Display name for a key code. Returns "?" for unknown.
    static func label(for keyCode: Int) -> String {
        if let s = baseMap[keyCode] { return s }
        return "?\(keyCode)"
    }

    /// Returns the modifier symbols for a flags mask, in canonical order ⌃⌥⇧⌘.
    static func modifierString(_ flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s
    }

    /// Pack flags to int, masked to the parts we care about.
    static func pack(_ flags: CGEventFlags) -> Int {
        var v = 0
        if flags.contains(.maskControl) { v |= 1 }
        if flags.contains(.maskAlternate) { v |= 2 }
        if flags.contains(.maskShift) { v |= 4 }
        if flags.contains(.maskCommand) { v |= 8 }
        return v
    }

    /// Build a friendly shortcut label such as "⌘⇧A" for keycode 0 + shift+cmd.
    static func shortcutLabel(keyCode: Int, flags: CGEventFlags) -> String? {
        let hasMod = flags.contains(.maskCommand)
            || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
        // Plain Tab without modifier is not a "shortcut"; alt/cmd-tab is.
        guard hasMod || keyCode == kVK_Tab && flags.contains(.maskAlternate) else {
            return nil
        }
        let mods = modifierString(flags)
        return mods + label(for: keyCode)
    }

    /// Static map. Covers the common ANSI keys + nav + function keys + numpad.
    /// Reference: HIToolbox/Events.h.
    static let baseMap: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "⇱", kVK_End: "⇲",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_Shift: "⇧", kVK_Control: "⌃", kVK_Option: "⌥", kVK_Command: "⌘",
        kVK_RightShift: "⇧R", kVK_RightControl: "⌃R", kVK_RightOption: "⌥R", kVK_RightCommand: "⌘R",
        kVK_CapsLock: "⇪", kVK_Function: "fn",
        kVK_ANSI_Keypad0: "K0", kVK_ANSI_Keypad1: "K1", kVK_ANSI_Keypad2: "K2",
        kVK_ANSI_Keypad3: "K3", kVK_ANSI_Keypad4: "K4", kVK_ANSI_Keypad5: "K5",
        kVK_ANSI_Keypad6: "K6", kVK_ANSI_Keypad7: "K7", kVK_ANSI_Keypad8: "K8",
        kVK_ANSI_Keypad9: "K9",
        kVK_ANSI_KeypadDecimal: "K.", kVK_ANSI_KeypadMultiply: "K*",
        kVK_ANSI_KeypadPlus: "K+", kVK_ANSI_KeypadDivide: "K/",
        kVK_ANSI_KeypadMinus: "K-", kVK_ANSI_KeypadEquals: "K=",
        kVK_ANSI_KeypadEnter: "K↩",
    ]
}
