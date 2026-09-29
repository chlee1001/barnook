import Testing
@testable import BarNook

struct AppVisibilityTests {
    @Test func ofReadsTheSets() {
        #expect(AppVisibility.of("a", hidden: [], alwaysHidden: []) == .shown)
        #expect(AppVisibility.of("a", hidden: ["a"], alwaysHidden: []) == .hidden)
        #expect(AppVisibility.of("a", hidden: [], alwaysHidden: ["a"]) == .alwaysHidden)
        #expect(AppVisibility.of("a", hidden: ["a"], alwaysHidden: ["a"]) == .alwaysHidden)
    }

    @Test(arguments: AppVisibility.allCases, AppVisibility.allCases)
    func applyLeavesTheAppInOneSetAndOthersAlone(from: AppVisibility, to: AppVisibility) {
        var hidden: Set = ["other"]
        var always: Set = ["another"]
        (hidden, always) = AppVisibility.apply(from, to: "a", hidden: hidden, alwaysHidden: always)
        (hidden, always) = AppVisibility.apply(to, to: "a", hidden: hidden, alwaysHidden: always)

        #expect(AppVisibility.of("a", hidden: hidden, alwaysHidden: always) == to)
        #expect(!(hidden.contains("a") && always.contains("a")))
        #expect(hidden.subtracting(["a"]) == ["other"])
        #expect(always.subtracting(["a"]) == ["another"])
    }

    @Test func shownClearsAnAppInBothSets() {
        let result = AppVisibility.apply(.shown, to: "a", hidden: ["a"], alwaysHidden: ["a"])
        #expect(result.hidden.isEmpty && result.alwaysHidden.isEmpty)
    }

    @Test func listChoicesFollowTheAlwaysHiddenSwitch() {
        #expect(AppVisibility.listSelectable(alwaysHiddenEnabled: true) == [.shown, .hidden, .alwaysHidden])
        #expect(AppVisibility.listSelectable(alwaysHiddenEnabled: false) == [.shown, .hidden])
    }

    @Test func dividerToggleMovesInAndOutOfAlwaysHidden() {
        #expect(AppVisibility.alwaysHiddenToggleTarget(current: .hidden, alwaysHiddenEnabled: false) == nil)
        #expect(AppVisibility.alwaysHiddenToggleTarget(current: .alwaysHidden, alwaysHiddenEnabled: true) == .shown)
        #expect(AppVisibility.alwaysHiddenToggleTarget(current: .shown, alwaysHiddenEnabled: true) == .alwaysHidden)
        #expect(AppVisibility.alwaysHiddenToggleTarget(current: .hidden, alwaysHiddenEnabled: true) == .alwaysHidden)
    }

    @Test func notes() {
        #expect(AppVisibility.note(isRunning: false, visibility: .hidden, alwaysHiddenEnabled: true) == .notRunning)
        #expect(AppVisibility.note(isRunning: true, visibility: .alwaysHidden, alwaysHiddenEnabled: false) == .alwaysHiddenPaused)
        #expect(AppVisibility.note(isRunning: true, visibility: .alwaysHidden, alwaysHiddenEnabled: true) == nil)
        #expect(AppVisibility.note(isRunning: true, visibility: .hidden, alwaysHiddenEnabled: false) == nil)
    }

    @Test func countsOnlyListedApps() {
        #expect(AppVisibility.counts(ids: [], hidden: ["a"], alwaysHidden: ["b"]) == (0, 0))
        let counts = AppVisibility.counts(ids: ["a", "b", "c"], hidden: ["a", "b", "x"], alwaysHidden: ["b", "y"])
        #expect(counts.hidden == 1)
        #expect(counts.always == 1)
    }

    @Test func searchIgnoresCaseAndAccents() {
        #expect(AppVisibility.matches(name: "Dropbox", query: "  "))
        #expect(AppVisibility.matches(name: "Dropbox", query: "DROP"))
        #expect(!AppVisibility.matches(name: "Dropbox", query: "dropbx"))
        #expect(AppVisibility.matches(name: "Café", query: "cafe"))
    }
}
