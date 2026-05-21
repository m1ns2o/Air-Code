import SwiftUI

public struct BottomPanelView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var command = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Terminal", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(8)
            .background(theme.panel)
            Divider().overlay(theme.border)
            ScrollView {
                Text(store.terminalOutput.isEmpty ? "$" : store.terminalOutput)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            HStack {
                Text("$")
                    .foregroundStyle(theme.muted)
                TextField("command", text: $command)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let line = command
                        command = ""
                        Task { await store.runCommand(line: line) }
                    }
            }
            .font(.caption.monospaced())
            .padding(8)
            .background(theme.editor)
        }
        .background(theme.editor)
    }
}
