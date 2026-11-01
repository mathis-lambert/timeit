import Foundation
import Testing
import TimeitCore

@testable import TimeitApp

@MainActor @Test func channelSubscriptionPersistsWithoutChangingWorkspace() throws {
    let suite = "TimeitTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let database = try LocalDatabase()
    let store = AppStore(database: database)
    let updater = AppUpdater(defaults: defaults, info: [:])
    #expect(updater.channel == .stable)
    #expect(updater.channel.allowedChannels.isEmpty)
    #expect(
        store.updateProfile(name: "Shared workspace", currency: "EUR", goal: 35, contributions: "0", incomeTax: "0"))
    for channel in UpdateChannel.allCases {
        updater.select(channel)
        #expect(AppUpdater(defaults: defaults, info: [:]).channel == channel)
        #expect(try database.load().document.profile.name == "Shared workspace")
    }
    #expect(UpdateChannel.beta.allowedChannels == ["beta"])
    #expect(UpdateChannel.nightly.allowedChannels == ["beta", "nightly"])
    updater.select(.stable)
    #expect(AppUpdater(defaults: defaults, info: ["TimeitReleaseChannel": "nightly"]).channel == .stable)
    updater.start()
    #expect(!updater.canCheck)
    #expect(updater.unavailableReason != nil)
}

@MainActor @Test func freshInstallUsesItsReleaseChannelButInvalidDistributionCannotStart() throws {
    let suite = "TimeitTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let updater = AppUpdater(defaults: defaults, info: ["TimeitReleaseChannel": "beta", "TimeitUpdatesEnabled": true])
    #expect(updater.channel == .beta)
    #expect(AppUpdater(defaults: defaults, info: ["TimeitReleaseChannel": "stable"]).channel == .beta)
    updater.start()
    #expect(updater.unavailableReason != nil)
    #expect(!updater.canCheck)
}

@MainActor @Test func cloudEntryPointsRemainDisabled() async throws {
    let store = AppStore(database: try LocalDatabase())
    #expect(!AppStore.cloudAvailable)
    await store.restoreConnection()
    await store.connect()
    await store.synchronize()
    #expect(!store.connected)
    #expect(!store.isConnecting)
    #expect(!store.isSyncing)
    #expect(store.syncLabel == "Sur ce Mac")
    #expect(store.serverURL == "https://api.timeit.mathislambert.fr")
}
