// Modified by Chaehyeon Lee (2026): BarNook permission wording.
import AppKit
import ApplicationServices
import Observation

/// The optional Accessibility permission. With it, Ellipsis can ask each app
/// whether it has a menu bar item. Without it, Ellipsis works the same but
/// the app pickers list every running app.
@MainActor
@Observable
final class AccessibilityPermission {
    enum Key {
        static let declined = "accessibilityDeclined"
    }

    private let store: UserDefaults
    private(set) var isTrusted: Bool
    private var observer: NSObjectProtocol?

    /// The user chose "Not Now" in the explanation dialog. Ellipsis does not
    /// ask again at launch, only from Settings.
    var hasDeclined: Bool {
        didSet { store.set(hasDeclined, forKey: Key.declined) }
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        isTrusted = AXIsProcessTrusted()
        hasDeclined = store.bool(forKey: Key.declined)
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

    func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// Asks at launch once. A "Not Now" is remembered. A "Grant Permission"
    /// that the user does not finish in System Settings is asked again next launch.
    func askAtLaunchIfNeeded() {
        guard !isTrusted, !hasDeclined else { return }
        ask()
    }

    /// The explanation dialog. "Grant Permission" adds BarNook to the
    /// Accessibility list and shows the system prompt with its "Open System
    /// Settings" button. "Not Now" records an opt-out.
    func ask() {
        let alert = NSAlert()
        alert.messageText = "Let BarNook see which apps have a menu bar item?"
        alert.informativeText = """
            With the Accessibility permission, the app pickers in Settings list only the apps that have a menu bar item. Without it, they list every running app.

            This is optional. BarNook hides and shows items the same way either way. It never reads or controls anything else, and you can change your mind in Settings at any time.
            """
        alert.addButton(withTitle: "Grant Permission")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            hasDeclined = false
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        } else {
            hasDeclined = true
        }
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
