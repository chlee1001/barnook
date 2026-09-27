import Foundation
import Testing
@testable import BarNook

/// MenuBarAgent matches the allow-list only against apps in /Applications.
/// An app anywhere else stays hidden while any restriction is active, so
/// BarNook must not treat it as a pin it can draw. See docs/spec.md.
@MainActor
struct MenuBarRestrictionTests {
    @Test func anAppInApplicationsIsReachable() {
        let url = URL(fileURLWithPath: "/Applications/Rectangle.app")
        #expect(MenuBarRestriction.isReachableByAllowList(url))
    }

    @Test func anAppInApplicationSupportIsNotReachable() {
        let url = URL(fileURLWithPath: "/Users/someone/Library/Application Support/SynologyDrive/SynologyDrive.app")
        #expect(!MenuBarRestriction.isReachableByAllowList(url))
    }

    @Test func anAppInAHomeApplicationsFolderIsNotReachable() {
        let url = URL(fileURLWithPath: "/Users/someone/Applications/Thing.app")
        #expect(!MenuBarRestriction.isReachableByAllowList(url))
    }

    /// A folder whose name merely starts with "/Applications" is not it.
    @Test func aLookalikePathIsNotReachable() {
        let url = URL(fileURLWithPath: "/ApplicationsOld/Thing.app")
        #expect(!MenuBarRestriction.isReachableByAllowList(url))
    }

    @Test func noBundleURLIsNotReachable() {
        #expect(!MenuBarRestriction.isReachableByAllowList(nil))
    }
}
