import SwiftUI

public struct AppShellView: View {
    @StateObject private var store = AirCodeStore()

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
                            .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
                        Divider().overlay(store.theme.border)
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
                    Divider().overlay(store.theme.border)
                    AgentChatView()
                        .environmentObject(store)
                        .frame(minWidth: 340, idealWidth: 390, maxWidth: 470)
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
