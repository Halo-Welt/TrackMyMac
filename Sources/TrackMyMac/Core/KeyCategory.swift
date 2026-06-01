import Foundation
import AppKit
import Carbon

/// Maps a CGKeyCode + flags to a coarse category. Avoids keylogger semantics.
enum KeyCategory {
    case letter, digit, symbol, whitespace, navigation, function, modifier, shortcut, other

    var raw: String {
        switch self {
        case .letter: return "letter"
        case .digit: return "digit"
        case .symbol: return "symbol"
        case .whitespace: return "whitespace"
        case .navigation: return "navigation"
        case .function: return "function"
        case .modifier: return "modifier"
        case .shortcut: return "shortcut"
        case .other: return "other"
        }
    }

    static func categorize(keyCode: CGKeyCode, flags: CGEventFlags, character: String?) -> KeyCategory {
        // Modifier-as-shortcut wins
        let cmd = flags.contains(.maskCommand)
        let ctrl = flags.contains(.maskControl)
        let opt = flags.contains(.maskAlternate)
        if cmd || ctrl || opt {
            return .shortcut
        }
        // Special key codes (subset; covers common navigation/function keys)
        switch Int(keyCode) {
        case kVK_Space, kVK_Tab, kVK_Return, kVK_ANSI_KeypadEnter:
            return .whitespace
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Delete,
             kVK_ForwardDelete, kVK_Escape:
            return .navigation
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
             kVK_F9, kVK_F10, kVK_F11, kVK_F12:
            return .function
        case kVK_Shift, kVK_Control, kVK_Option, kVK_Command, kVK_RightShift,
             kVK_RightControl, kVK_RightOption, kVK_RightCommand, kVK_CapsLock, kVK_Function:
            return .modifier
        default:
            break
        }
        if let c = character?.first {
            if c.isLetter { return .letter }
            if c.isNumber { return .digit }
            if c == " " || c == "\t" || c == "\n" { return .whitespace }
            if c.isPunctuation || c.isSymbol { return .symbol }
        }
        return .other
    }
}
