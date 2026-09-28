// Modified by Chaehyeon Lee (2026): Accessibility and Screen Recording are
// required; replaces the optional Accessibility permission.
import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// The two permissions BarNook requires. Accessibility reads the menu bar
/// layout and clicks the clock for the user in bar mode; Screen Recording
/// captures the status-item strip that covers the menu bar while the clock
/// opens Notification Center (see `docs/phase9.md`). Settings opens only once
/// both are granted; until then `PermissionsOnboarding` shows instead.
@MainActor
@Observable
final class Permissions {
    enum Kind: CaseIterable, Sendable {
        case accessibility, screenRecording

        var settingsURL: URL {
            switch self {
            case .accessibility:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            case .screenRecording:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            }
        }
    }

    private(set) var isTrusted: Bool
    private(set) var isScreenRecordingGranted: Bool
    /// Screen Recording was requested in this process. macOS applies a grant
    /// only after BarNook relaunches, so the onboarding offers a relaunch.
    private(set) var hasRequestedScreenRecording = false
    private var observer: NSObjectProtocol?
    private var poll: Task<Void, Never>?

    var areGranted: Bool { isTrusted && isScreenRecordingGranted }

    var missing: [Kind] {
        Kind.allCases.filter { !isGranted($0) }
    }

    init() {
        isTrusted = AXIsProcessTrusted()
        isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
        // macOS posts this when any app's Accessibility trust changes. The new
        // value is readable a moment later.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refresh()
            }
        }
    }

    func isGranted(_ kind: Kind) -> Bool {
        switch kind {
        case .accessibility: isTrusted
        case .screenRecording: isScreenRecordingGranted
        }
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
        isScreenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    /// Adds BarNook to the permission's list in System Settings with the
    /// system prompt, then opens that list.
    func request(_ kind: Kind) {
        switch kind {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            hasRequestedScreenRecording = true
            isScreenRecordingGranted = CGRequestScreenCaptureAccess()
        }
        if !isGranted(kind) {
            NSWorkspace.shared.open(kind.settingsURL)
        }
    }

    /// Re-reads both permissions every second while something shows them.
    /// Screen Recording posts no notification.
    func startPolling() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        poll?.cancel()
        poll = nil
    }

    /// Quits and opens BarNook again, so that a Screen Recording grant takes effect.
    func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Whether the app with `pid` has a menu bar item. Asks the app over
    /// Accessibility, so it must not run on the main thread: an unresponsive
    /// app blocks until the timeout.
    nonisolated static func hasMenuBarItem(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return false }
        var count: CFIndex = 0
        AXUIElementGetAttributeValueCount(bar as! AXUIElement, kAXChildrenAttribute as CFString, &count)
        return count > 0
    }
}
