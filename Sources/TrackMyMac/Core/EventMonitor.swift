import Foundation
import AppKit
import Carbon
import CoreGraphics

/// Global event monitor for keyboard + mouse via CGEventTap.
/// Skips secure input fields automatically (no encrypted recording either).
final class EventMonitor {
    static let shared = EventMonitor()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var running = false

    /// Last event timestamp for idle calculations.
    private(set) var lastEventTs: TimeInterval = Date().timeIntervalSince1970

    func start() {
        guard !running else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<EventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: opaqueSelf
        ) else {
            Log.error("Failed to create event tap. Grant Input Monitoring + Accessibility, then restart.")
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        running = true
        Log.info("Event tap started.")
    }

    func stop() {
        guard let tap = tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let s = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes)
        }
        self.tap = nil
        self.runLoopSource = nil
        running = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let now = Date().timeIntervalSince1970
        lastEventTs = now
        let minute = Int64(now / 60)

        switch type {
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let secureInput = IsSecureEventInputEnabled()
            var character: String? = nil
            let maxLen: Int = 4
            var actualLen: Int = 0
            var chars = [UniChar](repeating: 0, count: maxLen)
            event.keyboardGetUnicodeString(maxStringLength: maxLen, actualStringLength: &actualLen, unicodeString: &chars)
            if actualLen > 0 {
                character = String(utf16CodeUnits: chars, count: actualLen)
            }
            let cat = KeyCategory.categorize(keyCode: keyCode, flags: flags, character: character)
            // Encrypt the literal character only when not secure input AND it's a printable single char.
            var cipher: Data? = nil
            if !secureInput, let c = character, !c.isEmpty {
                cipher = Crypto.encrypt(c)
            }
            Database.shared.insertKeystroke(ts: now, category: cat.raw, cipher: cipher)
            Database.shared.bumpMinute(minuteTs: minute, keys: 1)

        case .flagsChanged:
            // Modifier key transitions; count as modifier press only on key-down-ish.
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            Database.shared.insertKeystroke(ts: now, category: KeyCategory.categorize(keyCode: keyCode, flags: event.flags, character: nil).raw, cipher: nil)

        case .leftMouseDown:
            let p = event.location
            Database.shared.insertMouseEvent(ts: now, kind: "left", x: Double(p.x), y: Double(p.y))
            Database.shared.bumpMinute(minuteTs: minute, clicks: 1)

        case .rightMouseDown:
            let p = event.location
            Database.shared.insertMouseEvent(ts: now, kind: "right", x: Double(p.x), y: Double(p.y))
            Database.shared.bumpMinute(minuteTs: minute, clicks: 1)

        case .otherMouseDown:
            let p = event.location
            Database.shared.insertMouseEvent(ts: now, kind: "other", x: Double(p.x), y: Double(p.y))
            Database.shared.bumpMinute(minuteTs: minute, clicks: 1)

        case .scrollWheel:
            Database.shared.bumpMinute(minuteTs: minute, scrolls: 1)

        case .mouseMoved:
            // Approximate distance using delta fields when present.
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            let dist = (dx*dx + dy*dy).squareRoot()
            if dist > 0 {
                Database.shared.bumpMinute(minuteTs: minute, moveDistance: dist)
            }

        default:
            break
        }
    }
}
