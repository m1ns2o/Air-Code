import Foundation
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
    #expect(store.selectedCodexModel == .auto)
    #expect(store.selectedHermesProvider == .auto)
    #expect(store.selectedHermesModel == .auto)
    #expect(store.selectedReasoningEffort == .auto)
    #expect(store.resumeAgentSession == true)
    #expect(store.isCavemanEnabled == false)
}

@Test func hermesRequestCarriesProviderAndModelStrings() {
    let request = StartAgentRequest(
        agent: "hermes",
        prompt: "hello",
        provider: HermesProviderOption.openAICodex.providerID,
        model: HermesModelOption.gpt55.modelID
    )

    #expect(request.provider == "openai-codex")
    #expect(request.model == "gpt-5.5")
}

@Test func terminalDataFrameUsesBinaryPrefix() {
    let frame = TerminalFrame.dataFrame(Data([0x41, 0x42]))

    #expect(Array(frame) == [TerminalFrame.data, 0x41, 0x42])
}

@Test func terminalResizeFrameUsesBigEndianBinaryPayload() {
    let frame = TerminalFrame.resizeFrame(cols: 132, rows: 43)

    #expect(Array(frame) == [TerminalFrame.resize, 0x00, 0x84, 0x00, 0x2B])
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
