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
    #expect(store.selectedClaudeModel == .auto)
    #expect(store.selectedHermesProvider == .auto)
    #expect(store.selectedHermesModel == .auto)
    #expect(store.selectedReasoningEffort == .auto)
    #expect(store.selectedSpeedMode == .auto)
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

@Test func agentRequestCarriesSpeedModeWhenSupported() {
    let codexRequest = StartAgentRequest(
        agent: "codex",
        prompt: "hello",
        speedMode: .fast
    )
    let hermesRequest = StartAgentRequest(
        agent: "hermes",
        prompt: "hello",
        speedMode: .fast
    )
    let claudeFastRequest = StartAgentRequest(
        agent: "claude",
        prompt: "hello",
        speedMode: .fast
    )

    #expect(codexRequest.speedMode == "fast")
    #expect(hermesRequest.speedMode == "auto")
    #expect(claudeFastRequest.speedMode == "auto")
}

@Test func agentRequestCarriesContextAttachments() {
    let request = StartAgentRequest(
        agent: "codex",
        prompt: "inspect this",
        context: [.file(path: "src/main.go")]
    )

    #expect(request.context.count == 1)
    #expect(request.context.first?.type == "file")
    #expect(request.context.first?.path == "src/main.go")
}

@Test func slashCommandSuggestionsFilterByPrefix() {
    let suggestions = SlashCommandOption.matching("pl", agent: "codex")

    #expect(suggestions.first?.command == "/plan")
}

@Test func slashCommandSuggestionsAreProviderAware() {
    let codexSuggestions = SlashCommandOption.matching("raw", agent: "codex")
    let claudeSuggestions = SlashCommandOption.matching("raw", agent: "claude")
    let opencodeSuggestions = SlashCommandOption.matching("raw", agent: "opencode")
    let hermesRollbackSuggestions = SlashCommandOption.matching("rollback", agent: "hermes")
    let codexRollbackSuggestions = SlashCommandOption.matching("rollback", agent: "codex")
    let speedSuggestions = SlashCommandOption.matching("spe", agent: "codex")

    #expect(codexSuggestions.first?.command == "/raw")
    #expect(claudeSuggestions.isEmpty)
    #expect(opencodeSuggestions.isEmpty)
    #expect(hermesRollbackSuggestions.first?.command == "/rollback")
    #expect(!codexRollbackSuggestions.contains { $0.command == "/rollback" })
    #expect(speedSuggestions.first?.command == "/speed")
}

@Test func contextMentionParserFindsMentionedPaths() {
    let paths = ContextMentionParser.mentionedPaths(in: "compare @src/main.go and @README.md, ignore @../secret")

    #expect(paths == ["src/main.go", "README.md"])
}

@Test func contextMentionParserReplacesActiveMention() {
    let prompt = ContextMentionParser.replacingActiveMention(in: "inspect @src/ma", with: "src/main.go")

    #expect(prompt == "inspect @src/main.go ")
}

@Test func slashCommandParserMapsPlanAndGoalToModes() {
    let plan = AgentPromptCommand.parse("/plan refactor this")
    let goal = AgentPromptCommand.parse("/goal finish the migration")
    let goals = AgentPromptCommand.parse("/goals")
    let hermesGoal = AgentPromptCommand.parse("/goal finish the migration", agent: "hermes")

    #expect(plan.prompt == "refactor this")
    #expect(plan.mode == .plan)
    #expect(goal.prompt == "finish the migration")
    #expect(goal.mode == .goal)
    #expect(goals.localAction == .showGoals)
    #expect(hermesGoal.prompt == "/goal finish the migration")
    #expect(hermesGoal.mode == .agent)
}

@Test func slashCommandParserMapsContextShortcuts() {
    let mention = AgentPromptCommand.parse("/mention src/main.go")
    let autoOn = AgentPromptCommand.parse("/auto-context on")
    let autoStatus = AgentPromptCommand.parse("/auto-context status")
    let permissions = AgentPromptCommand.parse("/permissions")
    let mcp = AgentPromptCommand.parse("/mcp")
    let skills = AgentPromptCommand.parse("/skills", agent: "codex")
    let hermesSkills = AgentPromptCommand.parse("/skills list", agent: "hermes")

    #expect(mention.localAction == .attachFile("src/main.go"))
    #expect(autoOn.localAction == .setAutoContext(true))
    #expect(autoStatus.localAction == .setAutoContext(nil))
    #expect(permissions.localAction == .showPermissions)
    #expect(mcp.localAction == .showIntegrations("mcp"))
    #expect(skills.localAction == .showIntegrations("skills"))
    #expect(hermesSkills.prompt == "/skills list")
}

@Test func slashCommandParserMapsSessionAndReasoningShortcuts() {
    let newRun = AgentPromptCommand.parse("/new clean task")
    let resumeRun = AgentPromptCommand.parse("/resume continue task")
    let ultrathink = AgentPromptCommand.parse("/ultrathink inspect carefully")
    let caveman = AgentPromptCommand.parse("/caveman fix")
    let maxEffort = AgentPromptCommand.parse("/effort max inspect carefully")

    #expect(newRun.prompt == "clean task")
    #expect(newRun.resumeSession == false)
    #expect(resumeRun.resumeSession == true)
    #expect(ultrathink.reasoningEffort == .xhigh)
    #expect(caveman.caveman == true)
    #expect(maxEffort.reasoningEffort == .max)
    #expect(maxEffort.prompt == "inspect carefully")
}

@Test func slashCommandParserMapsSpeedShortcuts() {
    let fast = AgentPromptCommand.parse("/fast on")
    let defaultMode = AgentPromptCommand.parse("/fast off")
    let speedPrompt = AgentPromptCommand.parse("/speed fast inspect quickly")

    #expect(fast.localAction == .setSpeed(.fast))
    #expect(defaultMode.localAction == .setSpeed(.auto))
    #expect(speedPrompt.speedMode == .fast)
    #expect(speedPrompt.prompt == "inspect quickly")
}

@Test func slashCommandParserMapsTaskShortcuts() {
    let review = AgentPromptCommand.parse("/review")
    let security = AgentPromptCommand.parse("/security-review auth")
    let initCodex = AgentPromptCommand.parse("/init", agent: "codex")
    let initClaude = AgentPromptCommand.parse("/init", agent: "claude")

    #expect(review.prompt.contains("Review the current changes"))
    #expect(security.prompt.contains("security risks"))
    #expect(security.prompt.contains("auth"))
    #expect(initCodex.prompt.contains("AGENTS.md"))
    #expect(initClaude.prompt.contains("CLAUDE.md"))
}

@Test func slashCommandParserMapsSearchToLocalAction() {
    let command = AgentPromptCommand.parse("/search terminal session")
    #expect(command.localAction == .search("terminal session"))
    #expect(command.prompt == "")
}

@Test func slashCommandParserPassesHermesNativeCommandsThrough() {
    let rollback = AgentPromptCommand.parse("/rollback 1", agent: "hermes")
    let skills = AgentPromptCommand.parse("/skills install example", agent: "hermes")
    let codexSkills = AgentPromptCommand.parse("/skills", agent: "codex")

    #expect(rollback.prompt == "/rollback 1")
    #expect(rollback.mode == .agent)
    #expect(skills.prompt == "/skills install example")
    #expect(skills.mode == .agent)
    #expect(codexSkills.localAction != nil)
}

@Test func promptHistoryNavigatorCyclesThroughUserPrompts() {
    var history = PromptHistoryNavigator()

    #expect(history.previous(current: "draft", history: ["first", "second", "second", "third"]) == "third")
    #expect(history.previous(current: "", history: ["first", "second", "third"]) == "second")
    #expect(history.previous(current: "", history: ["first", "second", "third"]) == "first")
    #expect(history.previous(current: "", history: ["first", "second", "third"]) == "first")
    #expect(history.next(history: ["first", "second", "third"]) == "second")
    #expect(history.next(history: ["first", "second", "third"]) == "third")
    #expect(history.next(history: ["first", "second", "third"]) == "draft")
    #expect(history.next(history: ["first", "second", "third"]) == nil)
}

@Test func terminalDataFrameUsesBinaryPrefix() {
    let frame = TerminalFrame.dataFrame(Data([0x41, 0x42]))

    #expect(Array(frame) == [TerminalFrame.data, 0x41, 0x42])
}

@Test func terminalResizeFrameUsesBigEndianBinaryPayload() {
    let frame = TerminalFrame.resizeFrame(cols: 132, rows: 43)

    #expect(Array(frame) == [TerminalFrame.resize, 0x00, 0x84, 0x00, 0x2B])
}

@Test func conflictSavePathSuggestsLocalCopyBesideOriginal() {
    #expect(ConflictSavePath.suggestedPath(for: "main.go") == "main.local.go")
    #expect(ConflictSavePath.suggestedPath(for: "src/main.go") == "src/main.local.go")
    #expect(ConflictSavePath.suggestedPath(for: "README") == "README.local")
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
