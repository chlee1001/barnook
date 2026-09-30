import Testing
@testable import BarNook

@Suite struct RunningAppsGroupTests {
    @Test func keepsEveryProcessOfAnApp() {
        // espanso runs two processes; the second owns the menu bar item.
        let groups = RunningApps.group([("espanso", 20521), ("other", 7), ("espanso", 20524)])
        #expect(groups.map(\.id) == ["espanso", "other"])
        #expect(groups.map(\.pids) == [[20521, 20524], [7]])
    }

    @Test func leavesOutProcessesWithoutAnIdentifier() {
        let groups = RunningApps.group([(nil, 1), ("a", 2), (nil, 3)])
        #expect(groups.map(\.id) == ["a"])
        #expect(groups.map(\.pids) == [[2]])
    }
}
