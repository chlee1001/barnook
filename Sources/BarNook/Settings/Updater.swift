import Observation
import Sparkle

/// Sparkle, checking the appcast that `SUFeedURL` in Info.plist names. The
/// updater is the source of truth for the automatic-check setting.
@MainActor
@Observable
final class Updater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var observation: NSKeyValueObservation?

    /// False while a check or an install is in progress.
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    init() {
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    /// Checks now and shows the result, including "up to date".
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
