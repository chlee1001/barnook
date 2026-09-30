// Modified by Chaehyeon Lee (2026): added allow-list reachability checks for pins,
// skipped assertions MenuBarAgent already holds, kept the previous assertion
// until a replacement takes effect, and kept quit apps on the allow-list.
import AppKit
import os

enum MenuBarRestrictionError: LocalizedError {
    case frameworkNotLoaded(String)
    case classesNotFound

    var errorDescription: String? {
        switch self {
        case .frameworkNotLoaded(let reason):
            "MenuBarClientCore did not load: \(reason)"
        case .classesNotFound:
            "The MBAssessmentMode classes do not exist in this version of macOS."
        }
    }
}

/// Assessment-mode assertions against `MenuBarAgent`, through the private
/// `MenuBarClientCore` framework. See `docs/spec.md`, "How it hides".
@MainActor
final class MenuBarRestriction {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let log = Logger(subsystem: "kr.co.devch.BarNook", category: "restriction")

    /// MenuBarAgent takes system items as integer codes. 0–6 match the public
    /// `AEMenuBarItem` constants in order; 8 is Control Center. Codes past the
    /// enum are ignored, so a generous range keeps every allowable item visible.
    private static let allSystemItems = (0...40).map { NSNumber(value: $0) }

    private let configurationClass: NSObject.Type
    private let assertionClass: NSObject.Type
    /// Every assertion not yet invalidated, by token, oldest first in
    /// `ledger`. Tokens only grow: an object identity can come back once an
    /// invalidated assertion is freed, and a late reply must not match it.
    private var assertions: [UInt64: NSObject] = [:]
    private var ledger = AssertionLedger<UInt64>()
    private var nextToken: UInt64 = 0
    /// What the bar shows, or is about to: the newest requested assertion.
    private var applied: AssertionPolicy.Applied?
    private var newest: UInt64?
    private var retry: Task<Void, Never>?
    private var retryAttempt = 0
    /// Callers waiting for the newest assertion to report back.
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []

    var isActive: Bool { !ledger.isEmpty }

    /// Returns once the newest assertion has reported back, or at once if
    /// it already has. MenuBarAgent lays out only after that.
    func waitUntilActivated() async {
        guard newest != nil else { return }
        await withCheckedContinuation { activationWaiters.append($0) }
    }

    init() throws {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil else {
            throw MenuBarRestrictionError.frameworkNotLoaded(String(cString: dlerror()))
        }
        guard
            let configurationClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
            let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
        else {
            throw MenuBarRestrictionError.classesNotFound
        }
        self.configurationClass = configurationClass
        self.assertionClass = assertionClass
    }

    /// Whether the allow-list can reach this app at all. `MenuBarAgent`
    /// matches it only against apps in `/Applications`, so an app that runs
    /// from anywhere else stays hidden while any restriction is active,
    /// whatever the allow-list says. See `docs/spec.md`, "How it hides".
    /// Letting such an app through, or hiding every other app to make room
    /// for it, buys the user nothing.
    static func isReachableByAllowList(_ bundleURL: URL?) -> Bool {
        guard let bundleURL else { return false }
        return bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/")
    }

    /// The running apps the allow-list cannot reach, by bundle identifier.
    static func unreachableRunningApps() -> Set<String> {
        var result = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, !isReachableByAllowList(app.bundleURL) else { continue }
            result.insert(id)
        }
        return result
    }

    /// Hides the given apps and shows every other running app and every system
    /// item. The allow-list is a snapshot of the running apps, so call this
    /// again when an app launches. An allow-list MenuBarAgent already holds
    /// is not asked for again.
    ///
    /// Activation is asynchronous. The newest assertion wins while several are
    /// alive, so older ones stay until a newer one reports success.
    /// Invalidating them earlier drops every restriction for a moment and every
    /// item flashes; a failed activation leaves the previous one live and is
    /// retried.
    func apply(hiddenBundleIdentifiers hidden: Set<String>) {
        retry?.cancel()
        retry = nil
        retryAttempt = 0
        activate(hidden: hidden)
    }

    private func activate(hidden: Set<String>) {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let agentPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent")
            .first?.processIdentifier
        let wanted = AssertionPolicy.Applied(
            allowList: AssertionPolicy.allowList(running: running, hidden: hidden, previous: applied?.allowList),
            agentPID: agentPID
        )
        switch AssertionPolicy.decide(wanted, previous: applied) {
        case .skip:
            Self.log.debug("skip: unchanged")
            return
        case let .activate(reason, added, removed):
            Self.log.info("activate reason=\(reason.rawValue, privacy: .public) added=\(added, privacy: .public) removed=\(removed, privacy: .public)")
        }
        applied = wanted

        let configuration = (configurationClass as AnyObject)
            .perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
            .perform(NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"),
                     with: Self.allSystemItems as NSArray, with: wanted.allowList as NSArray)?
            .takeUnretainedValue()
        let assertion = assertionClass.init()
        nextToken += 1
        let token = nextToken
        assertions[token] = assertion
        ledger.requested(token, key: wanted)
        newest = token
        let completion: @convention(block) (Any?) -> Void = { [weak self] error in
            let failure = error.map { String(describing: $0) }
            Task { @MainActor in
                self?.reported(token, failure: failure, hidden: hidden)
            }
        }
        _ = assertion.perform(NSSelectorFromString("activateWithConfiguration:completionHandler:"),
                              with: configuration, with: completion)
    }

    private func reported(_ token: UInt64, failure: String?, hidden: Set<String>) {
        if let failure {
            let outcome = ledger.failed(token)
            invalidate([token])
            guard outcome.wasNewest else {
                Self.log.error("failed (superseded or released): \(failure, privacy: .public)")
                return
            }
            applied = outcome.newestKey
            retryAttempt += 1
            guard let delay = AssertionPolicy.retryDelay(attempt: retryAttempt) else {
                Self.log.error("failed; kept previous; giving up after \(self.retryAttempt - 1) retries: \(failure, privacy: .public)")
                finishActivating(token)
                return
            }
            Self.log.error("failed; kept previous; retry \(self.retryAttempt) in \(delay, privacy: .public): \(failure, privacy: .public)")
            retry = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.activate(hidden: hidden)
            }
            finishActivating(token)
            return
        }
        // Unknown to the ledger: released while it was on its way. It must
        // not outlive the release.
        invalidate(ledger.succeeded(token) ?? [token])
        finishActivating(token)
    }

    /// Resumes the waiters once the newest assertion has reported back.
    private func finishActivating(_ token: UInt64) {
        guard token == newest else { return }  // an older one; the newest is still on its way
        newest = nil
        resumeWaiters()
    }

    private func invalidate(_ tokens: [UInt64]) {
        for token in tokens {
            _ = assertions.removeValue(forKey: token)?.perform(NSSelectorFromString("invalidate"))
        }
    }

    private func resumeWaiters() {
        let waiters = activationWaiters
        activationWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func release() {
        retry?.cancel()
        retry = nil
        retryAttempt = 0
        invalidate(ledger.releaseAll())
        applied = nil
        newest = nil
        resumeWaiters()
    }
}
