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

    var body: some View {
        if store.connectionState == .failed {
            VStack(spacing: 10) {
                Text("Connection failed")
                    .font(.headline)
                Text(store.errorMessage ?? "Check server URL and token.")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                Button("Retry") {
                    Task { await store.connect() }
                }
            }
            .padding(18)
            .background(theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
