import Foundation
import Observation
import Sparkle

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable, beta, nightly
    var id: Self { self }
    var title: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        case .nightly: "Nightly"
        }
    }
    /// Stable releases have no Sparkle channel and are always eligible.
    var allowedChannels: Set<String> {
        switch self {
        case .stable: []
        case .beta: ["beta"]
        case .nightly: ["beta", "nightly"]
        }
    }
    var explanation: String {
        switch self {
        case .stable: "Versions publiques validées."
        case .beta: "Versions de test et versions stables."
        case .nightly: "Versions de développement, betas et versions stables."
        }
    }
}

/// Sparkle owns checking, version comparison, downloads and installation.
/// The channel only filters one appcast; it never changes the app's identity or storage.
@MainActor @Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let feedURL = "https://timeit.mathislambert.fr/updates/appcast.xml"
    private(set) var channel: UpdateChannel
    private(set) var canCheck = false
    private(set) var sessionInProgress = false
    private(set) var automaticallyChecks = false
    private(set) var lastCheck: Date?
    private(set) var unavailableReason: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(defaults: UserDefaults = .standard, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.defaults = defaults
        channel =
            defaults.string(forKey: "updateChannel").flatMap(UpdateChannel.init(rawValue:))
            ?? (info["TimeitReleaseChannel"] as? String).flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        if info["TimeitUpdatesEnabled"] as? Bool != true {
            unavailableReason = "Les mises à jour sont disponibles dans les versions distribuées de Timeit."
        } else if info["CFBundleIdentifier"] as? String != "fr.mathislambert.Timeit"
            || info["SUFeedURL"] as? String != Self.feedURL
            || Data(base64Encoded: info["SUPublicEDKey"] as? String ?? "")?.count != 32
        {
            unavailableReason = "La configuration des mises à jour est invalide."
        }
        super.init()
        defaults.set(channel.rawValue, forKey: "updateChannel")
    }

    func start() {
        guard unavailableReason == nil, controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.sessionInProgress) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
            updater.observe(\.lastUpdateCheckDate) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
        ]
        do { try updater.start() } catch { unavailableReason = error.localizedDescription }
        refresh()
    }

    func select(_ channel: UpdateChannel) {
        guard controller?.updater.sessionInProgress != true, channel != self.channel else { return }
        self.channel = channel
        defaults.set(channel.rawValue, forKey: "updateChannel")
        controller?.updater.resetUpdateCycle()
    }

    func check() {
        guard canCheck else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channel.allowedChannels }

    private func refresh() {
        guard let updater = controller?.updater else { return }
        canCheck = unavailableReason == nil && updater.canCheckForUpdates
        sessionInProgress = updater.sessionInProgress
        automaticallyChecks = updater.automaticallyChecksForUpdates
        lastCheck = updater.lastUpdateCheckDate
    }
}
