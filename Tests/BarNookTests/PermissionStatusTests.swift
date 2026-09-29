import Testing
@testable import BarNook

struct PermissionStatusTests {
    private func status(_ ax: Bool, _ sr: Bool, requested: Bool = false) -> PermissionStatus {
        PermissionStatus(accessibility: ax, screenRecording: sr, hasRequestedScreenRecording: requested)
    }

    @Test func accessibilityStepIgnoresTheRequestFlag() {
        #expect(status(true, false, requested: true).step(.accessibility) == .allowed)
        #expect(status(false, false, requested: true).step(.accessibility) == .waiting)
    }

    @Test func screenRecordingWaitsForARelaunchOnceRequested() {
        #expect(status(false, true).step(.screenRecording) == .allowed)
        #expect(status(false, true, requested: true).step(.screenRecording) == .allowed)
        #expect(status(false, false, requested: true).step(.screenRecording) == .needsRelaunch)
        #expect(status(false, false).step(.screenRecording) == .waiting)
    }

    @Test func countsAndMissingKeepTheKindOrder() {
        #expect(status(true, true).allowedCount == 2)
        #expect(status(true, true).missing.isEmpty)
        #expect(status(true, false).allowedCount == 1)
        #expect(status(true, false).missing == [.screenRecording])
        #expect(status(false, true).missing == [.accessibility])
        #expect(status(false, false, requested: true).missing == [.accessibility, .screenRecording])
        #expect(status(false, false).allowedCount == 0)
    }

    @Test(arguments: [
        (true, true, false, PermissionStatus.Hint.ready),
        (true, false, true, .relaunch),
        (true, false, false, .allow([.screenRecording])),
        (false, true, false, .allow([.accessibility])),
        (false, false, true, .allow([.accessibility])),
        (false, false, false, .allow([.accessibility, .screenRecording])),
    ])
    func hintNamesTheNextStep(ax: Bool, sr: Bool, requested: Bool, hint: PermissionStatus.Hint) {
        #expect(status(ax, sr, requested: requested).hint == hint)
    }
}
