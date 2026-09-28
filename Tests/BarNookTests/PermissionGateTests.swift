import Testing
@testable import BarNook

@Suite struct PermissionGateTests {
    @Test func grantedPermissionsNeverShowTheOnboarding() {
        #expect(!PermissionGate.showsOnboarding(granted: true, trigger: .launch, skipsAtLaunch: false))
        #expect(!PermissionGate.showsOnboarding(granted: true, trigger: .settings, skipsAtLaunch: false))
    }

    @Test func aMissingPermissionShowsTheOnboardingAtLaunch() {
        #expect(PermissionGate.showsOnboarding(granted: false, trigger: .launch, skipsAtLaunch: false))
    }

    @Test func theVMSkipOnlyAppliesAtLaunch() {
        #expect(!PermissionGate.showsOnboarding(granted: false, trigger: .launch, skipsAtLaunch: true))
        #expect(PermissionGate.showsOnboarding(granted: false, trigger: .settings, skipsAtLaunch: true))
    }
}
