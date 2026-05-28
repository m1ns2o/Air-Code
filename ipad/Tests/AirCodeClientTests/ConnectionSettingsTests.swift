import Foundation
import SwiftUI
import Testing
@testable import AirCodeClient
#if os(macOS)
import AppKit
#endif

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
    #expect(store.selectedCodexApprovalMode == .serverDefault)
    #expect(store.selectedCodexSandboxMode == .serverDefault)
    #expect(store.selectedClaudePermissionMode == .serverDefault)
    #expect(store.selectedHermesPermissionMode == .serverDefault)
    #expect(store.resumeAgentSession == true)
    #expect(store.isCavemanEnabled == false)
    #expect(store.promptSteeringText == "")
}

@MainActor
@Test func editApprovalStatePersistsByProjectAndAgent() async {
    let projectID = "project-\(UUID().uuidString)"
    let hermesKey = "AirCode.resolvedEditApprovalRunIds.\(projectID).hermes"
    let codexKey = "AirCode.resolvedEditApprovalRunIds.\(projectID).codex"
    defer {
        UserDefaults.standard.removeObject(forKey: hermesKey)
        UserDefaults.standard.removeObject(forKey: codexKey)
    }

    let store = AirCodeStore(tokenStore: MemoryTokenStore())
    store.selectedProject = ProjectSummary(id: projectID, name: "Sandbox")
    await store.selectAgent("hermes")
    store.acceptEditApproval(runId: "run_approved")

    #expect(store.isEditApprovalResolved(runId: "run_approved"))

    let reopened = AirCodeStore(tokenStore: MemoryTokenStore())
    reopened.selectedProject = ProjectSummary(id: projectID, name: "Sandbox")
    await reopened.selectAgent("hermes")

    #expect(reopened.isEditApprovalResolved(runId: "run_approved"))

    await reopened.selectAgent("codex")
    #expect(!reopened.isEditApprovalResolved(runId: "run_approved"))
}

@Test func terminalBackgroundMatchesEditorBackground() {
    for themeID in AirCodeThemeID.allCases {
        let theme = themeID.theme
        #expect(theme.terminalBackground == theme.editor)
    }
}

@Test func editorAndTerminalBackgroundMatchSidebarPanelTone() {
    for themeID in AirCodeThemeID.allCases {
        let theme = themeID.theme
        #expect(theme.editor == theme.panel)
        #expect(theme.terminalBackground == theme.panel)
    }
}

@Test func promptInputBackgroundUsesOriginalEditorSurfaceTone() {
    #expect(AirCodeThemeID.materialOceanic.theme.promptInputBackground == Color(hex: 0x263238))
    #expect(AirCodeThemeID.materialLighter.theme.promptInputBackground == Color(hex: 0xFFFFFF))
    #expect(AirCodeThemeID.materialPalenight.theme.promptInputBackground == Color(hex: 0x292D3E))
    #expect(AirCodeThemeID.materialDarker.theme.promptInputBackground == Color(hex: 0x212121))
}

@Test func cursorUsesMaterialYellow() {
    #expect(AirCodeThemeID.materialOceanic.theme.cursorHex == 0xFFE082)
    #expect(AirCodeThemeID.materialLighter.theme.cursorHex == 0xF6A434)
    #expect(AirCodeThemeID.materialPalenight.theme.cursorHex == 0xFFE082)
    #expect(AirCodeThemeID.materialDarker.theme.cursorHex == 0xFFE082)
}

#if os(macOS)
@Test func codeEditorSelectionUsesYellowTintHue() {
    #expect(hexValue(AirCodeThemeID.materialOceanic.theme.codeEditorTheme.selectionColour) == 0xFFE082)
    #expect(hexValue(AirCodeThemeID.materialLighter.theme.codeEditorTheme.selectionColour) == 0xF7E7BD)
    #expect(hexValue(AirCodeThemeID.materialPalenight.theme.codeEditorTheme.selectionColour) == 0xFFE082)
    #expect(hexValue(AirCodeThemeID.materialDarker.theme.codeEditorTheme.selectionColour) == 0xFFE082)
}
#endif

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

#if os(macOS)
private func hexValue(_ color: NSColor) -> UInt32 {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    let red = UInt32((rgb.redComponent * 255).rounded())
    let green = UInt32((rgb.greenComponent * 255).rounded())
    let blue = UInt32((rgb.blueComponent * 255).rounded())
    return (red << 16) | (green << 8) | blue
}
#endif

@Test func agentRequestCarriesProviderPermissionOverrides() {
    let codexRequest = StartAgentRequest(
        agent: "codex",
        prompt: "hello",
        approvalMode: CodexApprovalMode.ask.rawValue,
        sandboxMode: CodexSandboxMode.workspaceWrite.rawValue
    )
    let claudeRequest = StartAgentRequest(
        agent: "claude",
        prompt: "hello",
        approvalMode: ClaudePermissionMode.acceptEdits.rawValue
    )
    let hermesRequest = StartAgentRequest(
        agent: "hermes",
        prompt: "hello",
        approvalMode: HermesPermissionMode.yolo.rawValue
    )

    #expect(codexRequest.approvalMode == "on-request")
    #expect(codexRequest.sandboxMode == "workspace-write")
    #expect(claudeRequest.approvalMode == "acceptEdits")
    #expect(claudeRequest.sandboxMode == "")
    #expect(hermesRequest.approvalMode == "yolo")
    #expect(hermesRequest.sandboxMode == "")
}

@Test func integrationInventoryDecodesNullItemsAsEmptyList() throws {
    let data = Data("""
    {
      "sections": [
        {
          "id": "hooks",
          "title": "Hooks",
          "description": "Provider hooks",
          "items": null
        }
      ]
    }
    """.utf8)

    let inventory = try JSONDecoder().decode(IntegrationInventory.self, from: data)

    #expect(inventory.sections.first?.id == "hooks")
    #expect(inventory.sections.first?.items == [])
}

@Test func permissionSnapshotDecodesNullCollectionsAsEmptyLists() throws {
    let data = Data("""
    {
      "projectId": "sample",
      "commandPolicy": {
        "enabled": true,
        "allowedCommands": null,
        "timeoutSeconds": 0,
        "terminalEnabled": true,
        "allowedShells": null,
        "maxSessions": 2
      },
      "agents": [
        {
          "id": "codex",
          "displayName": "Codex",
          "enabled": true,
          "approvalMode": "provider-default",
          "sandboxMode": "provider-default",
          "riskLevel": "medium",
          "notes": null
        }
      ]
    }
    """.utf8)

    let snapshot = try JSONDecoder().decode(PermissionSnapshot.self, from: data)

    #expect(snapshot.commandPolicy.allowedCommands == [])
    #expect(snapshot.commandPolicy.allowedShells == [])
    #expect(snapshot.commandPolicy.detachedTimeoutSeconds == 0)
    #expect(snapshot.agents.first?.notes == [])
}

@Test func providerStatusDecodesMissingOptionalFields() throws {
    let data = Data("""
    {
      "agent": "codex",
      "displayName": "Codex",
      "installed": true,
      "configured": true,
      "enabled": true,
      "messageCount": 2,
      "transcriptChars": 42,
      "notes": null
    }
    """.utf8)

    let status = try JSONDecoder().decode(ProviderStatusResponse.self, from: data)

    #expect(status.agent == "codex")
    #expect(status.messageCount == 2)
    #expect(status.transcriptChars == 42)
    #expect(status.notes == [])
    #expect(status.rawStatus == nil)
}

@Test func reviewFindingParserReadsSeverityPathLineMessages() {
    let text = """
    - HIGH src/main.go:42: unchecked error can hide save failure
    src/auth.swift:13 medium - token is logged
    normal prose without file reference
    """

    let findings = ReviewFindingParser.findings(in: text, source: "Codex")

    #expect(findings.count == 2)
    #expect(findings[0].severity == "high")
    #expect(findings[0].path == "src/main.go")
    #expect(findings[0].line == 42)
    #expect(findings[0].message == "unchecked error can hide save failure")
    #expect(findings[1].severity == "medium")
    #expect(findings[1].path == "src/auth.swift")
    #expect(findings[1].line == 13)
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
    #expect(claudeFastRequest.speedMode == "fast")
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

@Test func agentRequestCarriesPromptAttachments() {
    let attachment = AgentAttachment(
        id: "att_123",
        name: "screenshot.png",
        mimeType: "image/png",
        size: 128,
        kind: "image",
        path: ".aircode/attachments/att_123/original"
    )
    let request = StartAgentRequest(agent: "codex", prompt: "inspect image", attachments: [attachment])

    #expect(request.attachments.count == 1)
    #expect(request.attachments.first?.kind == "image")
}

@Test func mcpCatalogDecodesRemoteItem() throws {
    let data = Data("""
    {
      "items": [
        {
          "id": "github",
          "name": "github",
          "displayName": "GitHub",
          "description": "Repos",
          "source": "official",
          "installCommand": "remote https://example.test/mcp",
          "remoteUrl": "https://example.test/mcp",
          "requiresEnv": ["GITHUB_TOKEN"],
          "verified": true
        }
      ]
    }
    """.utf8)

    let response = try JSONDecoder().decode(MCPCatalogSearchResponse.self, from: data)

    #expect(response.items.first?.remoteUrl == "https://example.test/mcp")
    #expect(response.items.first?.requiresEnv == ["GITHUB_TOKEN"])
}

@Test func editorContextSnapshotPrefersSelection() {
    let text = "one\nlet answer = 42\nthree\n"
    let range = (text as NSString).range(of: "let answer = 42")
    let snapshot = EditorContextSnapshot.make(path: "src/main.swift", text: text, selection: range)

    #expect(snapshot.hasSelection)
    #expect(snapshot.attachment?.type == "selection")
    #expect(snapshot.attachment?.content == "let answer = 42")
    #expect(snapshot.attachment?.startLine == 2)
    #expect(snapshot.attachment?.endLine == 2)
}

@Test func editorContextSnapshotFallsBackToCursorWindow() {
    let lines = (1...140).map { "line \($0)" }.joined(separator: "\n")
    let cursorLocation = (lines as NSString).range(of: "line 80").location
    let snapshot = EditorContextSnapshot.make(path: "src/main.go", text: lines, selection: NSRange(location: cursorLocation, length: 0))

    #expect(!snapshot.hasSelection)
    #expect(snapshot.attachment?.type == "cursor")
    #expect(snapshot.attachment?.startLine == 20)
    #expect(snapshot.attachment?.endLine == 140)
    #expect(snapshot.attachment?.content?.contains("line 80") == true)
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
    let claudeFastSuggestions = SlashCommandOption.matching("fast", agent: "claude")
    let hermesFastSuggestions = SlashCommandOption.matching("fast", agent: "hermes")
    let claudeCodeReviewSuggestions = SlashCommandOption.matching("code", agent: "claude")
    let codexAppsSuggestions = SlashCommandOption.matching("apps", agent: "codex")

    #expect(codexSuggestions.first?.command == "/raw")
    #expect(claudeSuggestions.isEmpty)
    #expect(opencodeSuggestions.isEmpty)
    #expect(hermesRollbackSuggestions.first?.command == "/rollback")
    #expect(!codexRollbackSuggestions.contains { $0.command == "/rollback" })
    #expect(speedSuggestions.first?.command == "/speed")
    #expect(claudeFastSuggestions.first?.command == "/fast")
    #expect(hermesFastSuggestions.first?.command == "/fast")
    #expect(claudeCodeReviewSuggestions.contains { $0.command == "/code-review" })
    #expect(codexAppsSuggestions.first?.command == "/apps")
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
    let goalStatus = AgentPromptCommand.parse("/goal")
    let hermesGoal = AgentPromptCommand.parse("/goal finish the migration", agent: "hermes")

    #expect(plan.prompt == "/plan refactor this")
    #expect(plan.mode == .plan)
    #expect(goal.prompt == "/goal finish the migration")
    #expect(goal.mode == .goal)
    #expect(goalStatus.prompt == "/goal")
    #expect(goalStatus.localAction == nil)
    #expect(hermesGoal.prompt == "/goal finish the migration")
    #expect(hermesGoal.mode == .goal)
}

@Test func slashCommandParserMapsContextShortcuts() {
    let mention = AgentPromptCommand.parse("/mention src/main.go")
    let autoOn = AgentPromptCommand.parse("/auto-context on")
    let autoStatus = AgentPromptCommand.parse("/auto-context status")
    let steering = AgentPromptCommand.parse("/steering prefer small diffs")
    let steeringOff = AgentPromptCommand.parse("/steering off")
    let permissions = AgentPromptCommand.parse("/permissions")
    let mcp = AgentPromptCommand.parse("/mcp")
    let skills = AgentPromptCommand.parse("/skills", agent: "codex")
    let hermesSkills = AgentPromptCommand.parse("/skills list", agent: "hermes")
    let compact = AgentPromptCommand.parse("/compact")
    let context = AgentPromptCommand.parse("/context")

    #expect(mention.localAction == .attachFile("src/main.go"))
    #expect(autoOn.localAction == .setAutoContext(true))
    #expect(autoStatus.localAction == .setAutoContext(nil))
    #expect(steering.localAction == .setSteering("prefer small diffs"))
    #expect(steeringOff.localAction == .setSteering(""))
    #expect(permissions.prompt == "")
    #expect(permissions.localAction == .showPermissions)
    #expect(mcp.prompt == "")
    #expect(mcp.localAction == .providerCommand(kind: "mcp", command: "list"))
    #expect(skills.prompt == "")
    #expect(skills.localAction == .showIntegrations("skills"))
    #expect(hermesSkills.prompt == "")
    #expect(hermesSkills.localAction == .providerCommand(kind: "skills", command: "list"))
    #expect(compact.prompt == "/compact")
    #expect(context.prompt == "")
    #expect(context.localAction == .showContextUsage)
}

@Test func slashCommandParserMapsSessionAndReasoningShortcuts() {
    let newRun = AgentPromptCommand.parse("/new clean task")
    let resumeRun = AgentPromptCommand.parse("/resume continue task")
    let fallbackNewRun = AgentPromptCommand.parse("/new clean task", agent: "opencode")
    let fallbackResumeRun = AgentPromptCommand.parse("/resume continue task", agent: "opencode")
    let ultrathink = AgentPromptCommand.parse("/ultrathink inspect carefully")
    let caveman = AgentPromptCommand.parse("/caveman fix")
    let maxEffort = AgentPromptCommand.parse("/effort max inspect carefully")

    #expect(newRun.prompt == "clean task")
    #expect(newRun.resumeSession == false)
    #expect(newRun.localAction == nil)
    #expect(resumeRun.prompt == "continue task")
    #expect(resumeRun.resumeSession == true)
    #expect(resumeRun.localAction == nil)
    #expect(fallbackNewRun.prompt == "clean task")
    #expect(fallbackNewRun.resumeSession == false)
    #expect(fallbackResumeRun.resumeSession == true)
    #expect(ultrathink.reasoningEffort == .xhigh)
    #expect(caveman.caveman == true)
    #expect(maxEffort.reasoningEffort == .max)
    #expect(maxEffort.prompt == "inspect carefully")
}

@Test func slashCommandParserMapsSpeedShortcuts() {
    let fast = AgentPromptCommand.parse("/fast on")
    let claudeFast = AgentPromptCommand.parse("/fast", agent: "claude")
    let hermesFast = AgentPromptCommand.parse("/fast fast", agent: "hermes")
    let fallbackDefaultMode = AgentPromptCommand.parse("/fast off", agent: "opencode")
    let speedPrompt = AgentPromptCommand.parse("/speed fast inspect quickly")

    #expect(fast.prompt == "")
    #expect(fast.localAction == .setSpeed(.fast))
    #expect(claudeFast.prompt == "/fast")
    #expect(claudeFast.localAction == nil)
    #expect(hermesFast.prompt == "/fast fast")
    #expect(hermesFast.localAction == nil)
    #expect(fallbackDefaultMode.localAction == .setSpeed(.auto))
    #expect(speedPrompt.speedMode == .fast)
    #expect(speedPrompt.prompt == "inspect quickly")
}

@Test func slashCommandParserForwardsProviderModelDiffAndEffortWhenSupported() {
    let model = AgentPromptCommand.parse("/model sonnet", agent: "claude")
    let diff = AgentPromptCommand.parse("/diff", agent: "codex")
    let claudeEffort = AgentPromptCommand.parse("/effort high", agent: "claude")
    let codexEffort = AgentPromptCommand.parse("/effort max inspect carefully", agent: "codex")

    #expect(model.prompt == "")
    #expect(model.localAction == .message("Use the model menu in the chat header. Air Code sends the selected model to Codex, Claude Code, or Hermes on each run."))
    #expect(diff.prompt == "")
    #expect(diff.localAction == .openDiff(""))
    #expect(claudeEffort.prompt == "")
    #expect(claudeEffort.localAction == .setReasoning(.high))
    #expect(codexEffort.reasoningEffort == .max)
    #expect(codexEffort.prompt == "inspect carefully")
}

@Test func slashCommandParserMapsTaskShortcuts() {
    let review = AgentPromptCommand.parse("/review")
    let security = AgentPromptCommand.parse("/security-review auth")
    let initCodex = AgentPromptCommand.parse("/init", agent: "codex")
    let initClaude = AgentPromptCommand.parse("/init", agent: "claude")
    let fallbackReview = AgentPromptCommand.parse("/review", agent: "opencode")

    #expect(review.prompt == "/review")
    #expect(review.localAction == nil)
    #expect(security.prompt == "/security-review auth")
    #expect(security.localAction == nil)
    #expect(initCodex.prompt == "/init")
    #expect(initClaude.prompt == "/init")
    #expect(fallbackReview.prompt.contains("Review the current changes"))
}

@Test func slashCommandParserForwardsProviderClearWhenSupported() {
    let codexClear = AgentPromptCommand.parse("/clear", agent: "codex")
    let claudeClear = AgentPromptCommand.parse("/clear", agent: "claude")
    let opencodeClear = AgentPromptCommand.parse("/clear", agent: "opencode")

    #expect(codexClear.prompt == "")
    #expect(codexClear.localAction == .newSession)
    #expect(claudeClear.prompt == "")
    #expect(claudeClear.localAction == .newSession)
    #expect(opencodeClear.localAction == .newSession)
}

@Test func slashCommandParserForwardsAdditionalProviderWrappers() {
    let codexStop = AgentPromptCommand.parse("/stop", agent: "codex")
    let codexProcesses = AgentPromptCommand.parse("/ps", agent: "codex")
    let codexApps = AgentPromptCommand.parse("/apps", agent: "codex")
    let codexSandbox = AgentPromptCommand.parse("/sandbox-add-read-dir /tmp", agent: "codex")
    let codexSideTask = AgentPromptCommand.parse("/side", agent: "codex")
    let claudeBranch = AgentPromptCommand.parse("/branch", agent: "claude")
    let claudeRewind = AgentPromptCommand.parse("/rewind", agent: "claude")
    let claudeCodeReview = AgentPromptCommand.parse("/code-review high", agent: "claude")
    let claudeAlias = AgentPromptCommand.parse("/allowed-tools", agent: "claude")
    let claudeRename = AgentPromptCommand.parse("/rename Air Code", agent: "claude")
    let claudePlugins = AgentPromptCommand.parse("/plugins", agent: "claude")
    let hermesQueue = AgentPromptCommand.parse("/queue", agent: "hermes")
    let hermesHooks = AgentPromptCommand.parse("/hooks", agent: "hermes")
    let codexDoctor = AgentPromptCommand.parse("/doctor", agent: "codex")
    let hermesDoctor = AgentPromptCommand.parse("/doctor", agent: "hermes")
    let hermesProvider = AgentPromptCommand.parse("/provider openai-codex", agent: "hermes")
    let hermesResume = AgentPromptCommand.parse("/resume 20260522_103012_abc123", agent: "hermes")

    #expect(codexStop.prompt == "")
    #expect(codexStop.localAction == .stopRun)
    #expect(codexProcesses.prompt == "/ps")
    #expect(codexApps.prompt == "")
    #expect(codexApps.localAction == .showIntegrations("apps"))
    #expect(codexSandbox.prompt == "/sandbox-add-read-dir /tmp")
    #expect(codexSideTask.prompt == "/side")
    #expect(claudeBranch.prompt == "/branch")
    #expect(claudeRewind.prompt == "/rewind")
    #expect(claudeCodeReview.prompt == "/code-review high")
    #expect(claudeAlias.prompt == "")
    #expect(claudeAlias.localAction == .showPermissions)
    #expect(claudeRename.prompt == "/rename Air Code")
    #expect(claudePlugins.localAction == .providerCommand(kind: "plugins", command: "list"))
    #expect(hermesQueue.prompt == "/queue")
    #expect(hermesHooks.localAction == .providerCommand(kind: "hooks", command: "list"))
    #expect(codexDoctor.localAction == .message("Codex does not expose a safe headless doctor command here. Use `/status` for Air Code settings or run the provider doctor/debug command in the terminal."))
    #expect(hermesDoctor.localAction == .providerCommand(kind: "doctor", command: "check"))
    #expect(hermesProvider.prompt == "/provider openai-codex")
    #expect(hermesResume.prompt == "/resume 20260522_103012_abc123")
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
    #expect(skills.prompt == "")
    #expect(skills.localAction == .message("Use the Integrations panel or Hermes terminal commands to install or remove skills. `/skills` and `/skills list` run a read-only provider CLI list command."))
    #expect(codexSkills.prompt == "")
    #expect(codexSkills.localAction == .showIntegrations("skills"))
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

@Test func runtimeEventShortensRunId() {
    let event = AgentRuntimeEvent(runId: "run_1234567890abcdef", agent: "codex", kind: "started", title: "Started")

    #expect(event.shortRunId == "run_1234...cdef")
}

@Test func conflictSavePathSuggestsLocalCopyBesideOriginal() {
    #expect(ConflictSavePath.suggestedPath(for: "main.go") == "main.local.go")
    #expect(ConflictSavePath.suggestedPath(for: "src/main.go") == "src/main.local.go")
    #expect(ConflictSavePath.suggestedPath(for: "README") == "README.local")
}

@MainActor
@Test func selectingOpenFileLeavesDiffViewerMode() async {
    let store = AirCodeStore(tokenStore: MemoryTokenStore())
    store.openFiles = [
        OpenFile(path: "src/main.go", content: "package main\n", savedContent: "package main\n", version: "v1", conflictVersion: nil)
    ]
    store.selectedDiffPath = "src/main.go"
    store.selectedDiff = "@@ -1 +1 @@"
    store.isDiffViewerVisible = true

    await store.openFile(path: "src/main.go")

    #expect(store.selectedFilePath == "src/main.go")
    #expect(store.isDiffViewerVisible == false)
    #expect(store.selectedDiffPath == nil)
    #expect(store.selectedDiff.isEmpty)
}

@Test func editorFindEngineFindsAndWrapsMatches() {
    let text = "alpha beta Alpha"
    let matches = EditorFindEngine.matches(in: text, query: "alpha")

    #expect(matches.count == 2)
    #expect(matches[0].location == 0)
    #expect(matches[1].location == 11)
    #expect(EditorFindEngine.nextIndex(currentIndex: nil, matchCount: matches.count, direction: .forward) == 0)
    #expect(EditorFindEngine.nextIndex(currentIndex: 1, matchCount: matches.count, direction: .forward) == 0)
    #expect(EditorFindEngine.nextIndex(currentIndex: 0, matchCount: matches.count, direction: .backward) == 1)
}

@Test func editorFindEngineReplacesCurrentAndAllMatches() {
    let text = "foo bar foo"
    let matches = EditorFindEngine.matches(in: text, query: "foo")
    let replaced = EditorFindEngine.replace(in: text, range: matches[0], with: "baz")
    let all = EditorFindEngine.replaceAll(in: text, query: "foo", replacement: "baz")

    #expect(replaced == "baz bar foo")
    #expect(all.text == "baz bar baz")
    #expect(all.count == 2)
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
