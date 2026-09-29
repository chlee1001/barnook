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

    @Test(arguments: [
        (AppVisibility.alwaysHidden, false, AppVisibility?.some(.shown)),
        (.hidden, false, nil),
        (.shown, false, nil),
        (.alwaysHidden, true, .shown),
        (.hidden, true, .alwaysHidden),
        (.shown, true, .alwaysHidden),
    ])
    func dividerToggle(current: AppVisibility, enabled: Bool, expected: AppVisibility?) {
        #expect(AppVisibility.alwaysHiddenToggleTarget(current: current, alwaysHiddenEnabled: enabled) == expected)
    }

    @Test func moveReordersWithinAGroup() {
        let lists = HiddenLists(hidden: ["a", "b", "c"], alwaysHidden: ["d"])
        #expect(AppVisibility.move("c", to: .hidden, before: "a", in: lists).hidden == ["c", "a", "b"])
        #expect(AppVisibility.move("a", to: .hidden, before: nil, in: lists).hidden == ["b", "c", "a"])
        #expect(AppVisibility.move("b", to: .hidden, before: "b", in: lists) == lists)
    }

    @Test func moveAcrossGroupsInsertsBeforeTheAnchor() {
        let lists = HiddenLists(hidden: ["a", "b", "c"], alwaysHidden: ["d"])
        #expect(AppVisibility.move("s", to: .hidden, before: "b", in: lists)
            == HiddenLists(hidden: ["a", "s", "b", "c"], alwaysHidden: ["d"]))
        #expect(AppVisibility.move("a", to: .alwaysHidden, before: nil, in: lists)
            == HiddenLists(hidden: ["b", "c"], alwaysHidden: ["d", "a"]))
        #expect(AppVisibility.move("b", to: .shown, before: "x", in: lists)
            == HiddenLists(hidden: ["a", "c"], alwaysHidden: ["d"]))
    }

    @Test func moveTakesAnAppInBothListsOutOfBoth() {
        let lists = HiddenLists(hidden: ["a", "x"], alwaysHidden: ["x", "d"])
        #expect(AppVisibility.move("x", to: .hidden, before: "a", in: lists)
            == HiddenLists(hidden: ["x", "a"], alwaysHidden: ["d"]))
        #expect(AppVisibility.move("x", to: .shown, before: nil, in: lists)
            == HiddenLists(hidden: ["a"], alwaysHidden: ["d"]))
    }

    @Test func moveWithAMissingAnchorAppends() {
        let lists = HiddenLists(hidden: ["a", "b"], alwaysHidden: ["d"])
        #expect(AppVisibility.move("s", to: .hidden, before: "d", in: lists).hidden == ["a", "b", "s"])
        #expect(AppVisibility.move("s", to: .alwaysHidden, before: "gone", in: lists).alwaysHidden == ["d", "s"])
    }

    @Test func stepMovesOneSlotAndStopsAtTheEnds() {
        let lists = HiddenLists(hidden: ["a", "b", "c"], alwaysHidden: ["d", "e"])
        #expect(AppVisibility.step("b", by: -1, in: lists).hidden == ["b", "a", "c"])
        #expect(AppVisibility.step("b", by: 1, in: lists).hidden == ["a", "c", "b"])
        #expect(AppVisibility.step("d", by: 1, in: lists).alwaysHidden == ["e", "d"])
        #expect(AppVisibility.step("a", by: -1, in: lists) == lists)
        #expect(AppVisibility.step("c", by: 1, in: lists) == lists)
        #expect(AppVisibility.step("s", by: 1, in: lists) == lists)
        #expect(AppVisibility.step("a", by: 2, in: lists).hidden == ["b", "c", "a"])
        #expect(AppVisibility.step("a", by: 3, in: lists) == lists)
    }

    @Test func dropMovesOnlyListedAllowedAppsInDragOrder() {
        let lists = HiddenLists(hidden: ["a", "b", "c"], alwaysHidden: ["d"])
        let result = AppVisibility.drop(
            ["s", "c", "d", "gone"], into: .hidden, before: "b",
            listed: ["a", "b", "c", "d", "s"], in: lists,
            allowed: { $0 != .alwaysHidden }
        )
        #expect(result?.lists == HiddenLists(hidden: ["a", "s", "c", "b"], alwaysHidden: ["d"]))
        #expect(result?.moved == "c")
    }

    @Test func dropThatChangesNothingIsNil() {
        let lists = HiddenLists(hidden: ["a", "b"], alwaysHidden: ["d"])
        let listed: Set = ["a", "b", "d"]
        #expect(AppVisibility.drop(["d"], into: .hidden, before: nil, listed: listed, in: lists,
                                   allowed: { _ in false }) == nil)
        #expect(AppVisibility.drop(["gone"], into: .hidden, before: nil, listed: listed, in: lists,
                                   allowed: { _ in true }) == nil)
        #expect(AppVisibility.drop(["a"], into: .hidden, before: "b", listed: listed, in: lists,
                                   allowed: { _ in true }) == nil)
    }

    @Test func placeCountsFromOneInTheAppsList() throws {
        let lists = HiddenLists(hidden: ["a", "b", "c"], alwaysHidden: ["d", "e"])
        #expect(try #require(AppVisibility.place(of: "b", in: lists)) == (2, 3))
        #expect(try #require(AppVisibility.place(of: "e", in: lists)) == (2, 2))
        #expect(AppVisibility.place(of: "s", in: lists) == nil)
    }

    /// Every move across groups, by mode (list or by position) and the
    /// always-hidden switch (spec F4, F7).
    @Test(arguments: [
        // divider, enabled, from, to, allowed
        (false, true, AppVisibility.hidden, AppVisibility.shown, true),
        (false, true, .shown, .hidden, true),
        (false, true, .hidden, .alwaysHidden, true),
        (false, true, .shown, .alwaysHidden, true),
        (false, true, .alwaysHidden, .shown, true),
        (false, true, .alwaysHidden, .hidden, true),
        (false, false, .hidden, .shown, true),
        (false, false, .shown, .hidden, true),
        (false, false, .hidden, .alwaysHidden, false),
        (false, false, .shown, .alwaysHidden, false),
        (false, false, .alwaysHidden, .shown, true),
        (false, false, .alwaysHidden, .hidden, true),
        (true, true, .hidden, .shown, false),
        (true, true, .shown, .hidden, false),
        (true, true, .hidden, .alwaysHidden, true),
        (true, true, .shown, .alwaysHidden, true),
        (true, true, .alwaysHidden, .shown, true),
        (true, true, .alwaysHidden, .hidden, false),
        (true, false, .hidden, .shown, false),
        (true, false, .shown, .hidden, false),
        (true, false, .hidden, .alwaysHidden, false),
        (true, false, .shown, .alwaysHidden, false),
        (true, false, .alwaysHidden, .shown, true),
        (true, false, .alwaysHidden, .hidden, false),
    ])
    func canMoveAcrossGroups(divider: Bool, enabled: Bool, from: AppVisibility, to: AppVisibility, allowed: Bool) {
        for canReorder in [true, false] {
            #expect(AppVisibility.canMove(
                from: from, to: to, isDividerActive: divider,
                isAlwaysHiddenEnabled: enabled, canReorder: canReorder
            ) == allowed)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func canMoveWithinAGroupFollowsReorder(divider: Bool, enabled: Bool) {
        for group in [AppVisibility.hidden, .alwaysHidden] {
            #expect(AppVisibility.canMove(from: group, to: group, isDividerActive: divider,
                                          isAlwaysHiddenEnabled: enabled, canReorder: true))
            #expect(!AppVisibility.canMove(from: group, to: group, isDividerActive: divider,
                                           isAlwaysHiddenEnabled: enabled, canReorder: false))
        }
        #expect(!AppVisibility.canMove(from: .shown, to: .shown, isDividerActive: divider,
                                       isAlwaysHiddenEnabled: enabled, canReorder: true))
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
