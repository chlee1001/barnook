import Testing
@testable import BarNook

struct AppVisibilityTests {
    @Test func ofReadsTheLists() {
        #expect(AppVisibility.of("a", in: HiddenLists()) == .shown)
        #expect(AppVisibility.of("a", in: HiddenLists(hidden: ["a"])) == .hidden)
        #expect(AppVisibility.of("a", in: HiddenLists(alwaysHidden: ["a"])) == .alwaysHidden)
        #expect(AppVisibility.of("a", in: HiddenLists(hidden: ["a"], alwaysHidden: ["a"])) == .alwaysHidden)
    }

    @Test(arguments: AppVisibility.allCases, AppVisibility.allCases)
    func applyLeavesTheAppInOneListAndOthersInOrder(from: AppVisibility, to: AppVisibility) {
        var lists = HiddenLists(hidden: ["p", "q"], alwaysHidden: ["r", "s"])
        lists = AppVisibility.apply(from, to: "a", in: lists)
        lists = AppVisibility.apply(to, to: "a", in: lists)

        #expect(AppVisibility.of("a", in: lists) == to)
        #expect(!(lists.hidden.contains("a") && lists.alwaysHidden.contains("a")))
        #expect(lists.hidden.filter { $0 != "a" } == ["p", "q"])
        #expect(lists.alwaysHidden.filter { $0 != "a" } == ["r", "s"])
    }

    @Test func applyAppendsToTheEnd() {
        let result = AppVisibility.apply(.hidden, to: "x", in: HiddenLists(hidden: ["a", "b"], alwaysHidden: []))
        #expect(result.hidden == ["a", "b", "x"])
    }

    @Test func applyToTheCurrentStateKeepsTheSlot() {
        let lists = HiddenLists(hidden: ["a", "x", "b"], alwaysHidden: ["c"])
        #expect(AppVisibility.apply(.hidden, to: "x", in: lists) == lists)
        #expect(AppVisibility.apply(.alwaysHidden, to: "c", in: lists) == lists)
    }

    @Test func shownClearsAnAppInBothLists() {
        let result = AppVisibility.apply(.shown, to: "a", in: HiddenLists(hidden: ["a"], alwaysHidden: ["a"]))
        #expect(result.hidden.isEmpty && result.alwaysHidden.isEmpty)
    }

    @Test func groupsFollowTheListsAndSkipUnlisted() {
        let none = AppVisibility.groups(listed: [], in: HiddenLists(hidden: ["a"], alwaysHidden: ["b"]))
        #expect(none.hidden.isEmpty && none.alwaysHidden.isEmpty && none.shown.isEmpty)
        let groups = AppVisibility.groups(
            listed: ["a", "b", "c", "d"],
            in: HiddenLists(hidden: ["c", "x", "a"], alwaysHidden: ["d"])
        )
        #expect(groups.hidden == ["c", "a"])
        #expect(groups.alwaysHidden == ["d"])
        #expect(groups.shown == ["b"])
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

    @Test func searchIgnoresCaseAndAccents() {
        #expect(AppVisibility.matches(name: "Dropbox", query: "  "))
        #expect(AppVisibility.matches(name: "Dropbox", query: "DROP"))
        #expect(!AppVisibility.matches(name: "Dropbox", query: "dropbx"))
        #expect(AppVisibility.matches(name: "Café", query: "cafe"))
    }
}
