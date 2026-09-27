import AppKit

/// A menu bar item for the VM tests. The title comes from CFBundleName, so
/// one binary serves FixtureA.app, FixtureB.app and so on with their own
/// bundle identifiers. "Mark" writes a file named after the bundle
/// identifier in the home directory, so a test can tell that a click
/// reached this app's menu. With BarNookFixtureMenuCount in Info.plist
/// the app is a regular app with that many menus, so it takes most of the
/// menu bar while it is frontmost: the stand-in for a notch.
final class Fixture: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let count = Bundle.main.object(forInfoDictionaryKey: "BarNookFixtureMenuCount") as? Int, count > 0 {
            let mainMenu = NSMenu()
            for number in 1...count {
                let title = NSMenuItem(title: "Menu \(number)", action: nil, keyEquivalent: "")
                title.submenu = NSMenu(title: "Menu \(number)")
                title.submenu?.addItem(withTitle: "Nothing", action: nil, keyEquivalent: "")
                mainMenu.addItem(title)
            }
            NSApp.mainMenu = mainMenu
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Fixture"
        let menu = NSMenu()
        menu.addItem(withTitle: "Mark", action: #selector(mark), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        self.item = item
    }

    @objc private func mark() {
        let name = Bundle.main.bundleIdentifier ?? "fixture"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(name).marked")
        try? Date().description.write(to: url, atomically: true, encoding: .utf8)
    }
}

let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
