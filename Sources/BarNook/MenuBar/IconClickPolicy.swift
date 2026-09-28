/// What a click on the BarNook icon does. Whenever the set is shown in bar
/// mode and the bar is closed (a pin closed it, or the last pin went), the
/// first click brings the bar back and the second hides the set.
enum IconClickPolicy {
    enum Action: Equatable { case show, reopenBar, hide }

    static func action(isShown: Bool, inBar: Bool, isBarOpen: Bool) -> Action {
        if !isShown { return .show }
        if inBar, !isBarOpen { return .reopenBar }
        return .hide
    }
}
