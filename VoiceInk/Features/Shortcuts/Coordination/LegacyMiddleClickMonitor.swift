import AppKit
import Foundation

private let middleMouseButtonNumber = 2
private let enabledKey = "isMiddleClickToggleEnabled"
private let activationDelayKey = "middleClickActivationDelay"
// Upstream's registered default up to 2.13 (AppDefaults), used when the key is absent.
private let defaultActivationDelayMilliseconds = 200

/// Local patch (fork esimioni/VoiceInk): the "hold the middle mouse button" recording trigger that
/// VoiceInk shipped up to 2.13, ported as-is. Upstream 2.20 replaced it with mouse-button shortcuts
/// that fire on press and swallow the button, which takes the plain middle click away from every
/// other app (closing tabs, opening links in a new tab).
///
/// Global NSEvent monitors are passive: every click still reaches the app under the cursor, and only
/// a press held for `middleClickActivationDelay` ms toggles the recorder. They also run outside the
/// CGEvent tap that serves the keyboard shortcuts, so a dead tap leaves this trigger alive.
/// The settings keep their pre-2.20 UserDefaults keys, with no UI since upstream dropped it:
///   defaults write com.prakashjoshipax.VoiceInk isMiddleClickToggleEnabled -bool true
///   defaults write com.prakashjoshipax.VoiceInk middleClickActivationDelay -int 400
@MainActor
final class LegacyMiddleClickMonitor {
    private var monitors: [Any] = []
    private var holdTask: Task<Void, Never>?

    func start(onHold: @escaping @MainActor () async -> Void) {
        stop()
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }

        let down = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard event.buttonNumber == middleMouseButtonNumber else { return }
            Task { @MainActor in
                self?.beginHold(onHold: onHold)
            }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard event.buttonNumber == middleMouseButtonNumber else { return }
            Task { @MainActor in
                self?.holdTask?.cancel()
            }
        }
        monitors = [down, up].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        holdTask?.cancel()
        holdTask = nil
    }

    private func beginHold(onHold: @escaping @MainActor () async -> Void) {
        holdTask?.cancel()
        let delay = Self.activationDelayNanoseconds()
        holdTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return  // Released before the delay: a plain middle click, left to the app under the cursor.
            }
            await onHold()
        }
    }

    private static func activationDelayNanoseconds() -> UInt64 {
        let stored = UserDefaults.standard.object(forKey: activationDelayKey) as? Int
        let milliseconds = max(0, stored ?? defaultActivationDelayMilliseconds)
        return UInt64(milliseconds) * 1_000_000
    }
}
