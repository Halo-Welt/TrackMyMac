import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import AppKit

/// Periodically samples idle / screen state and writes per-minute aggregates.
final class ActivitySampler {
    static let shared = ActivitySampler()
    private var timer: Timer?
    private let idleThresholdSec: Double = 60   // user is "active" if input within last 60 sec
    private let sampleEvery: TimeInterval = 5.0

    func start() {
        let t = Timer.scheduledTimer(withTimeInterval: sampleEvery, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let idle = systemIdleSeconds()
        let screenOn = !isScreenLocked()
        let now = Date().timeIntervalSince1970
        let minute = Int64(now / 60)
        let active = idle < idleThresholdSec
        // Each tick contributes `sampleEvery` seconds (capped at 60 / minute).
        Database.shared.bumpMinute(
            minuteTs: minute,
            activeDelta: active ? Int(sampleEvery) : 0,
            screenOnDelta: screenOn ? Int(sampleEvery) : 0
        )
    }

    /// Seconds since last HID input system-wide.
    private func systemIdleSeconds() -> Double {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator)
        guard result == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)
        if entry == 0 { return 0 }
        defer { IOObjectRelease(entry) }
        var props: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) != KERN_SUCCESS {
            return 0
        }
        guard let dict = props?.takeRetainedValue() as? [String: Any],
              let idleNS = dict["HIDIdleTime"] as? UInt64 else { return 0 }
        return Double(idleNS) / 1_000_000_000.0
    }

    private func isScreenLocked() -> Bool {
        // Heuristic: when locked, frontmost app may still be set, but we use CGSession info.
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = dict["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        if let loginDone = dict["kCGSSessionLoginDoneKey"] as? Bool, !loginDone { return true }
        return false
    }
}
