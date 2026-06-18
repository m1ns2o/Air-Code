import SwiftUI

public struct AppShellView: View {
    @StateObject private var store = AirCodeStore()
    @AppStorage("AirCode.layout.sidebarWidth") private var sidebarWidth = 260.0
    @AppStorage("AirCode.layout.chatWidth") private var chatWidth = 390.0
    @State private var sidebarDragStart: Double?
    @State private var chatDragStart: Double?
    #if DEBUG
    @State private var didRunLaunchAutomation = false
    #endif

    private let sidebarRange = 190.0...420.0
    private let chatRange = 300.0...560.0

    public init() {}

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Divider().overlay(store.theme.border)
                HStack(spacing: 0) {
                    if store.isSidebarVisible {
                        ProjectSidebarView()
                            .environmentObject(store)
                            .frame(width: CGFloat(sidebarWidth))
                        PanelResizeHandle(accessibilityLabel: "Resize folder sidebar")
                            .gesture(sidebarResizeGesture)
                    }
                    VStack(spacing: 0) {
                        EditorPaneView()
                            .environmentObject(store)
                        if store.isBottomPanelVisible {
                            Divider().overlay(store.theme.border)
                            BottomPanelView()
                                .environmentObject(store)
                                .frame(height: 210)
                        }
                    }
                    PanelResizeHandle(accessibilityLabel: "Resize chat sidebar")
                        .gesture(chatResizeGesture)
                    AgentChatView()
                        .environmentObject(store)
                        .frame(width: CGFloat(chatWidth))
                }
            }
            ConnectionOverlayView()
                .environmentObject(store)
            if let draft = store.fileCreationDraft {
                NewProjectFileDialog(draft: draft)
                    .environmentObject(store)
                    .environment(\.airCodeTheme, store.theme)
                    .id(draft.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(20)
            }
        }
        .environment(\.airCodeTheme, store.theme)
        .background(store.theme.background)
        .foregroundStyle(store.theme.foreground)
        .task {
            await store.maintainConnection()
        }
        #if DEBUG
        .task(id: store.connectionState) {
            await runLaunchAutomationIfNeeded()
        }
        #endif
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                store.toggleSidebar()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .keyboardShortcut("b", modifiers: [.command])
            Text("Air Code")
                .font(.headline)
                .foregroundStyle(store.theme.accent)
            Text(store.selectedProject?.name ?? "No Project")
                .font(.caption)
                .foregroundStyle(store.theme.muted)
            Text(store.connectionState.rawValue)
                .font(.caption)
                .foregroundStyle(store.connectionState == .connected ? store.theme.green : store.theme.muted)
            Spacer()
            ThemeMenuView()
                .environmentObject(store)
            Button {
                store.toggleBottomPanel()
            } label: {
                Image(systemName: "rectangle.bottomthird.inset.filled")
            }
            .keyboardShortcut("j", modifiers: [.command])
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(store.theme.red)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(store.theme.panel)
    }

    private var sidebarResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if sidebarDragStart == nil {
                    sidebarDragStart = sidebarWidth
                }
                sidebarWidth = clamp((sidebarDragStart ?? sidebarWidth) + value.translation.width, to: sidebarRange)
            }
            .onEnded { _ in
                sidebarDragStart = nil
            }
    }

    private var chatResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if chatDragStart == nil {
                    chatDragStart = chatWidth
                }
                chatWidth = clamp((chatDragStart ?? chatWidth) - value.translation.width, to: chatRange)
            }
            .onEnded { _ in
                chatDragStart = nil
            }
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    #if DEBUG
    @MainActor
    private func runLaunchAutomationIfNeeded() async {
        guard !didRunLaunchAutomation,
              store.connectionState == .connected,
              let prompt = ProcessInfo.processInfo.environment["AIRCODE_AUTORUN_PROMPT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return
        }
        didRunLaunchAutomation = true
        print("[AirCodeDebugAutomation] starting")
        if store.selectedProject == nil {
            if let recent = store.recentProjects.first {
                await store.openRecentProject(recent)
            } else if let root = store.workspaceRoots.first {
                await store.openWorkspaceFolder(rootId: root.id, path: ".")
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await store.runAgent(prompt: prompt)
        print("[AirCodeDebugAutomation] prompt submitted")
    }
    #endif
}

private struct NewProjectFileDialog: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let draft: FileCreationDraft
    @State private var fileName = ""
    @State private var isCreating = false
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayPath: String {
        draft.parentPath == "." ? "Project root" : draft.parentPath
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isCreating {
                        store.cancelFileCreation()
                    }
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New File")
                            .font(.headline)
                            .foregroundStyle(theme.foreground)
                        Text(displayPath)
                            .font(.caption)
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        store.cancelFileCreation()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(theme.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreating)
                    .accessibilityLabel("Close New File Dialog")
                }

                TextField("filename.ext", text: $fileName)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(theme.editor)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(isFocused ? theme.accent : theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .focused($isFocused)
                    .submitLabel(.done)
                    .disabled(isCreating)
                    .onSubmit { create() }

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") {
                        store.cancelFileCreation()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.muted)
                    .disabled(isCreating)

                    Button {
                        create()
                    } label: {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty || isCreating)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(maxWidth: 400, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(theme.panel)
            .foregroundStyle(theme.foreground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
            .padding(.horizontal, 24)
        }
        .task {
            isFocused = true
        }
    }

    private func create() {
        guard !trimmedName.isEmpty, !isCreating else { return }
        let name = trimmedName
        isCreating = true
        Task {
            let didCreate = await store.createProjectFile(named: name)
            await MainActor.run {
                if !didCreate {
                    isCreating = false
                }
            }
        }
    }
}

private struct ThemeMenuView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme

    var body: some View {
        Menu {
            ForEach(AirCodeThemeID.allCases) { themeID in
                Button {
                    store.setTheme(themeID)
                } label: {
                    Label(themeID.theme.name, systemImage: themeID == store.selectedThemeID ? "checkmark" : "circle")
                }
            }
        } label: {
            Image(systemName: "paintpalette")
                .foregroundStyle(theme.muted)
        }
        .menuStyle(.button)
    }
}

private struct PanelResizeHandle: View {
    @Environment(\.airCodeTheme) private var theme
    let accessibilityLabel: String

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 9)
            .overlay {
                Rectangle()
                    .fill(theme.border)
                    .frame(width: 1)
            }
            .overlay {
                Capsule()
                    .fill(theme.muted.opacity(0.34))
                    .frame(width: 2, height: 28)
                    .opacity(0.7)
            }
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct ConnectionOverlayView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var serverURL = ""
    @State private var token = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case serverURL
        case token
    }

    var body: some View {
        if store.connectionState == .failed {
            ZStack {
                theme.background.opacity(0.72)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(theme.red)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connection failed")
                                .font(.headline)
                            Text(store.errorMessage ?? "Check server URL and token.")
                                .font(.caption)
                                .foregroundStyle(theme.muted)
                                .lineLimit(2)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.muted)
                        TextField("http://192.168.1.120:8080", text: $serverURL)
                            .focused($focusedField, equals: .serverURL)
                            .autocorrectionDisabled()
                            .onSubmit { focusedField = .token }
                            .padding(10)
                            .background(theme.editor)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auth token")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.muted)
                        SecureField("Bearer token", text: $token)
                            .focused($focusedField, equals: .token)
                            .autocorrectionDisabled()
                            .onSubmit { connectWithEditedSettings() }
                            .padding(10)
                            .background(theme.editor)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await store.connect() }
                        } label: {
                            Label("Retry Saved", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            connectWithEditedSettings()
                        } label: {
                            Label("Save & Connect", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                    }
                }
                .padding(20)
                .frame(width: 460)
                .background(theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .onAppear(perform: syncFields)
            .onChange(of: store.settings) { _, _ in syncFields() }
        }
    }

    private var canSave: Bool {
        URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil &&
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func syncFields() {
        serverURL = store.settings.serverURL
        token = store.settings.token
        focusedField = serverURL.isEmpty ? .serverURL : .token
    }

    private func connectWithEditedSettings() {
        guard canSave else { return }
        store.updateConnectionSettings(serverURL: serverURL, token: token)
        Task { await store.connect() }
    }
}
