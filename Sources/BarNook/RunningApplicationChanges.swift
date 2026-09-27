import AppKit

extension NSWorkspace {
    /// Yields when an app starts or quits. `didLaunchApplicationNotification`
    /// is not posted for `LSUIElement` apps, and apps with a menu bar item
    /// mostly are, so this watches `runningApplications` instead.
    static func runningApplicationChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observation = shared.observe(\.runningApplications) { _, _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in observation.invalidate() }
        }
    }
}
