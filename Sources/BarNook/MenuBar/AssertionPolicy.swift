import Foundation

/// When `MenuBarRestriction` needs a new assertion, and which assertions it
/// may drop. Pure, so the rules are tested without MenuBarAgent.
enum AssertionPolicy {
    /// What an assertion asks MenuBarAgent for. The agent's pid is part of
    /// it: a restarted MenuBarAgent has forgotten every assertion.
    struct Applied: Equatable, Sendable {
        var allowList: [String]
        var agentPID: pid_t?
    }

    enum Decision: Equatable {
        case skip
        case activate(reason: Reason, added: [String], removed: [String])

        enum Reason: String {
            case fresh, agentRestarted, allowListChanged
        }
    }

    /// Skips an assertion MenuBarAgent already holds. A new one for the
    /// same allow-list changes nothing on the bar and makes MenuBarAgent lay
    /// out again, which it does on every running-apps change.
    static func decide(_ wanted: Applied, previous: Applied?) -> Decision {
        guard let previous else {
            return .activate(reason: .fresh, added: wanted.allowList, removed: [])
        }
        if wanted == previous { return .skip }
        let added = Set(wanted.allowList).subtracting(previous.allowList).sorted()
        let removed = Set(previous.allowList).subtracting(wanted.allowList).sorted()
        let reason: Decision.Reason = wanted.agentPID == previous.agentPID ? .allowListChanged : .agentRestarted
        return .activate(reason: reason, added: added, removed: removed)
    }

    /// The wait before the given retry of a failed activation; nil once
    /// three retries have failed.
    static func retryDelay(attempt: Int) -> Duration? {
        switch attempt {
        case 1: .milliseconds(250)
        case 2: .seconds(1)
        case 3: .seconds(4)
        default: nil
        }
    }
}

/// The assertions `MenuBarRestriction` holds, oldest first. An assertion is
/// dropped only once a newer one has taken effect, so the bar is never left
/// without one mid-replacement; a failed activation leaves the previous
/// assertion live. `release` empties the ledger, and any activation still in
/// flight then reports for a token the ledger no longer knows: the caller
/// invalidates that one too, or it would outlive the release.
struct AssertionLedger<Token: Hashable> {
    private struct Entry {
        var token: Token
        var key: AssertionPolicy.Applied
        var succeeded = false
    }

    private var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    mutating func requested(_ token: Token, key: AssertionPolicy.Applied) {
        entries.append(Entry(token: token, key: key))
    }

    /// The older tokens to invalidate now that `token` took effect, or nil
    /// when the ledger does not hold `token`, which the caller then
    /// invalidates itself.
    mutating func succeeded(_ token: Token) -> [Token]? {
        guard let index = entries.firstIndex(where: { $0.token == token }) else { return nil }
        entries[index].succeeded = true
        let older = entries[..<index].map(\.token)
        entries.removeFirst(index)
        return older
    }

    /// The failed token leaves the ledger and must be invalidated; the
    /// others stay. `wasNewest` tells the caller to retry, and `newestKey`
    /// is what the bar still shows: the newest assertion that took effect.
    mutating func failed(_ token: Token) -> (wasNewest: Bool, newestKey: AssertionPolicy.Applied?) {
        guard let index = entries.firstIndex(where: { $0.token == token }) else {
            return (false, entries.last(where: \.succeeded)?.key)
        }
        let wasNewest = index == entries.count - 1
        entries.remove(at: index)
        return (wasNewest, entries.last(where: \.succeeded)?.key)
    }

    /// Every token, for invalidation; the ledger is then empty.
    mutating func releaseAll() -> [Token] {
        defer { entries = [] }
        return entries.map(\.token)
    }
}
