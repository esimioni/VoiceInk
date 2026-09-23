import Foundation

// Tests for the local patch LegacyMiddleClickMonitor (fork esimioni/VoiceInk). They live outside
// the Xcode project, so upstream's targets never conflict with them, and they compile together
// with the real source file:
//   swiftc -parse-as-library -o /tmp/legacy-middle-click-tests \
//     VoiceInk/Features/Shortcuts/Coordination/LegacyMiddleClickMonitor.swift \
//     LocalPatchTests/LegacyMiddleClickMonitorTests.swift && /tmp/legacy-middle-click-tests
// update-voiceink.sh runs them before every build. They drive beginHold/endHold directly (the
// NSEvent monitors only forward to them), with the activation delay set in the registration
// domain, so nothing is written to any defaults domain.

@MainActor
final class Probe {
    var fired = false
    var completed = false
    var cancelled = false
}

@main
@MainActor
struct LegacyMiddleClickMonitorTests {
    static let activationDelayMs = 50

    static func main() async {
        UserDefaults.standard.register(defaults: ["middleClickActivationDelay": activationDelayMs])
        var failures = 0
        failures += await check("release after the delay keeps the action alive", releaseAfterDelayKeepsActionAlive)
        failures += await check("release before the delay is a plain click", releaseBeforeDelayIsPlainClick)
        failures += await check("stop() before the delay drops the pending hold", stopBeforeDelayDropsHold)
        guard failures == 0 else {
            print("FAIL: \(failures) LegacyMiddleClickMonitor test(s)")
            exit(1)
        }
        print("OK: LegacyMiddleClickMonitor")
    }

    static func check(_ name: String, _ test: () async -> Bool) async -> Int {
        let passed = await test()
        print("\(passed ? "ok  " : "FAIL") \(name)")
        return passed ? 0 : 1
    }

    static func sleep(ms: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    // 24/11/2026, on 2.27: a hold past the delay fires toggleRecorderPanel, whose stop awaits the
    // whole transcription, and the release that ends the hold arrives in the middle of it. The
    // transcription honours cancellation since 2.25 (e43058f), so a release that cancels the action
    // turned every mouse-stopped dictation into "Transcription Failed: CancellationError".
    static func releaseAfterDelayKeepsActionAlive() async -> Bool {
        let monitor = LegacyMiddleClickMonitor()
        let probe = Probe()
        monitor.beginHold {
            probe.fired = true
            do {
                try await Task.sleep(nanoseconds: 200_000_000)  // the transcription
                probe.completed = true
            } catch {
                probe.cancelled = true
            }
        }
        await sleep(ms: activationDelayMs + 100)  // held past the delay: the action is running
        monitor.endHold()  // the button comes up mid-transcription
        await sleep(ms: 400)
        return probe.fired && probe.completed && !probe.cancelled
    }

    static func releaseBeforeDelayIsPlainClick() async -> Bool {
        let monitor = LegacyMiddleClickMonitor()
        let probe = Probe()
        monitor.beginHold { probe.fired = true }
        await sleep(ms: 10)
        monitor.endHold()
        await sleep(ms: activationDelayMs + 150)
        return !probe.fired
    }

    static func stopBeforeDelayDropsHold() async -> Bool {
        let monitor = LegacyMiddleClickMonitor()
        let probe = Probe()
        monitor.beginHold { probe.fired = true }
        await sleep(ms: 10)
        monitor.stop()
        await sleep(ms: activationDelayMs + 150)
        return !probe.fired
    }
}