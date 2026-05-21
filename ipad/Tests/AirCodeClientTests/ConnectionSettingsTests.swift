import Testing
@testable import AirCodeClient

@MainActor
@Test func storeBootstrapsDevelopmentConnectionSettings() {
    let tokenStore = MemoryTokenStore()
    let store = AirCodeStore(tokenStore: tokenStore)

    #expect(store.settings == .developmentDefault)
    #expect(tokenStore.savedSettings == .developmentDefault)
}

@MainActor
@Test func storeKeepsPreviouslySavedConnectionSettings() {
    let saved = ConnectionSettings(serverURL: "https://air.example.test", token: "saved-token")
    let tokenStore = MemoryTokenStore(loadedSettings: saved)
    let store = AirCodeStore(tokenStore: tokenStore)

    #expect(store.settings == saved)
    #expect(tokenStore.savedSettings == nil)
}

@MainActor
@Test func chatControlsDefaultToAgentWithoutExtras() {
    let store = AirCodeStore(tokenStore: MemoryTokenStore())

    #expect(store.selectedAgent == "codex")
    #expect(store.selectedAgentMode == .agent)
    #expect(store.isUltrathinkEnabled == false)
    #expect(store.isCavemanEnabled == false)
}

private final class MemoryTokenStore: TokenStore {
    private let loadedSettings: ConnectionSettings?
    private(set) var savedSettings: ConnectionSettings?

    init(loadedSettings: ConnectionSettings? = nil) {
        self.loadedSettings = loadedSettings
    }

    func load() -> ConnectionSettings? {
        loadedSettings
    }

    func save(_ settings: ConnectionSettings) {
        savedSettings = settings
    }
}
