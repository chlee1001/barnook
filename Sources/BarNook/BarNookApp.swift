import AppKit

/// Plain AppKit entry point. The SwiftUI `App` with a `Settings` scene never
/// opened its window from a status item action on macOS 27, so the app owns
/// its windows itself and hosts SwiftUI views in them.
@main
enum BarNookApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
