import SwiftUI

public struct ProjectSidebarView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var isOpenFolderPresented = false
    @State private var mode: SidebarMode = .explorer

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(theme.border)
            switch mode {
            case .explorer:
                explorer
            case .search:
                ProjectSearchView()
                    .environmentObject(store)
            case .sourceControl:
                SourceControlSidebarView()
                    .environmentObject(store)
            }
        }
        .background(theme.panel)
        .sheet(isPresented: $isOpenFolderPresented) {
            RemoteFolderPickerView()
                .environmentObject(store)
                .environment(\.airCodeTheme, theme)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                    Text(store.selectedProject?.name ?? "No Folder")
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    isOpenFolderPresented = true
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Remote Folder")
            }

            HStack(spacing: 4) {
                ForEach(SidebarMode.allCases) { item in
                    Button {
                        mode = item
                    } label: {
                        sidebarModeIcon(item)
                            .frame(width: 30, height: 26)
                            .background(mode == item ? activeModeColor(item).opacity(0.2) : theme.elevated.opacity(0.7))
                            .foregroundStyle(mode == item ? activeModeColor(item) : theme.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
                Spacer()
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func sidebarModeIcon(_ item: SidebarMode) -> some View {
        if item == .sourceControl {
            GitGraphIcon()
                .frame(width: 17, height: 17)
        } else {
            Image(systemName: item.symbol)
                .font(.caption.weight(.semibold))
        }
    }

    private func activeModeColor(_ item: SidebarMode) -> Color {
        theme.accent
    }

    private var explorer: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(store.treeEntries["."] ?? []) { entry in
                    TreeNodeView(entry: entry, depth: 0)
                        .environmentObject(store)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
    }
}

private enum SidebarMode: String, CaseIterable, Identifiable {
    case explorer
    case search
    case sourceControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explorer: return "Explorer"
        case .search: return "Search"
        case .sourceControl: return "Source Control"
        }
    }

    var symbol: String {
        switch self {
        case .explorer: return "folder"
        case .search: return "magnifyingglass"
        case .sourceControl: return "sourcecontrol"
        }
    }
}

private struct SourceControlSidebarView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var commitMessage = ""
    @State private var isStagedExpanded = true
    @State private var isChangesExpanded = true

    private var stagedChanges: [GitChange] {
        store.gitChanges.filter(\.isStaged)
    }

    private var unstagedChanges: [GitChange] {
        store.gitChanges.filter(\.isUnstaged)
    }

    private var gitAccent: Color {
        theme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GitGraphIcon()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(gitAccent)
                Text("Source Control")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                Spacer()
                Text("\(store.gitChanges.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(gitAccent)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(gitAccent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Button {
                    Task { await store.refreshGitStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(gitAccent)
                .accessibilityLabel("Refresh Source Control")
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            if store.gitSummary?.isGitRepository != false {
                gitSummaryBar
                    .padding(.horizontal, 10)
                    .padding(.top, 8)

                commitBox
                    .padding(10)
            }

            Divider().overlay(theme.border)

            if store.selectedProject == nil {
                ContentUnavailableView("No Folder", systemImage: "folder", description: Text("Open a folder to see Git changes."))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.gitSummary?.isGitRepository == false {
                initializeRepositoryView
            } else if store.gitChanges.isEmpty {
                ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("Working tree clean."))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        SourceControlSection(
                            title: "Staged Changes",
                            count: stagedChanges.count,
                            isExpanded: $isStagedExpanded,
                            trailingAction: stagedChanges.isEmpty ? nil : SourceControlSectionAction(
                                symbol: "minus",
                                label: "Unstage All",
                                action: { Task { await store.unstage(paths: stagedChanges.map(\.path)) } }
                            )
                        ) {
                            ForEach(stagedChanges) { change in
                                SourceControlChangeRow(change: change, placement: .staged)
                                    .environmentObject(store)
                            }
                        }

                        SourceControlSection(
                            title: "Changes",
                            count: unstagedChanges.count,
                            isExpanded: $isChangesExpanded,
                            trailingAction: unstagedChanges.isEmpty ? nil : SourceControlSectionAction(
                                symbol: "plus",
                                label: "Stage All",
                                action: { Task { await store.stage(paths: unstagedChanges.map(\.path)) } }
                            )
                        ) {
                            ForEach(unstagedChanges) { change in
                                SourceControlChangeRow(change: change, placement: .unstaged)
                                    .environmentObject(store)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .task(id: store.selectedProject?.id) {
            await store.refreshGitStatus()
        }
    }

    private var initializeRepositoryView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 18)
            GitGraphIcon()
                .frame(width: 42, height: 42)
                .foregroundStyle(gitAccent)
            Text("Initialize Repository")
                .font(.headline)
            Text("This folder is not currently tracked by Git.")
                .font(.caption)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.initGitRepository() }
            } label: {
                Label("Initialize Repository", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .background(gitAccent.opacity(0.18))
            .foregroundStyle(gitAccent)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .disabled(store.isGitOperationRunning)
            .padding(.top, 4)
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var gitSummaryBar: some View {
        if let summary = store.gitSummary {
            HStack(spacing: 7) {
                branchMenu
                Spacer(minLength: 6)
                if summary.ahead > 0 {
                    Label("\(summary.ahead)", systemImage: "arrow.up")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(gitAccent)
                }
                if summary.behind > 0 {
                    Label("\(summary.behind)", systemImage: "arrow.down")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.accent)
                }
                if !summary.hasRemote {
                    Text("No remote")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.muted)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(theme.elevated.opacity(0.72))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border.opacity(0.75)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var branchMenu: some View {
        Menu {
            if store.gitBranches.isEmpty {
                Text("No local branches")
            } else {
                ForEach(store.gitBranches) { branch in
                    Button {
                        Task { await store.checkoutBranch(branch) }
                    } label: {
                        Label(branch.name, systemImage: branch.current ? "checkmark" : "circle")
                    }
                    .disabled(branch.current)
                }
            }
        } label: {
            HStack(spacing: 7) {
                GitGraphIcon()
                    .frame(width: 14, height: 14)
                Text(store.gitSummary?.branch.isEmpty == false ? store.gitSummary?.branch ?? "Branch" : "detached")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(gitAccent)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(gitAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.button)
    }

    private var commitBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $commitMessage, prompt: Text("Message (⌘ Enter to commit)").foregroundStyle(theme.isLight ? theme.foreground.opacity(0.62) : theme.foreground.opacity(0.86)), axis: .vertical)
                .font(.caption)
                .lineLimit(2...4)
                .padding(8)
                .background(theme.editor)
                .tint(gitAccent)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(commitMessage.isEmpty ? theme.border : gitAccent.opacity(0.55)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .submitLabel(.done)

            HStack(spacing: 6) {
                Button {
                    Task {
                        let didCommit = await store.commit(message: commitMessage)
                        if didCommit {
                            commitMessage = ""
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        GitGraphIcon()
                            .frame(width: 13, height: 13)
                        Text("Commit")
                    }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .background(canCommit ? gitAccent.opacity(0.18) : theme.elevated)
                .foregroundStyle(canCommit ? gitAccent : theme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(!canCommit)
                .keyboardShortcut(.return, modifiers: [.command])

                Button {
                    Task { await store.stage(paths: unstagedChanges.map(\.path)) }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(theme.elevated)
                .foregroundStyle(unstagedChanges.isEmpty ? theme.muted.opacity(0.5) : gitAccent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(unstagedChanges.isEmpty)
                .accessibilityLabel("Stage All Changes")
            }

            HStack(spacing: 6) {
                gitOperationButton("Pull", systemImage: "arrow.down", operation: .pull)
                gitOperationButton("Push", systemImage: "arrow.up", operation: .push)
                gitOperationButton("Sync", systemImage: "arrow.triangle.2.circlepath", operation: .sync)
            }
        }
    }

    private func gitOperationButton(_ title: String, systemImage: String, operation: AirCodeStore.GitRemoteOperation) -> some View {
        Button {
            Task { await store.runGitRemoteOperation(operation) }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
        }
        .buttonStyle(.plain)
        .background(canRunRemoteOperation ? theme.elevated : theme.elevated.opacity(0.45))
        .foregroundStyle(canRunRemoteOperation ? gitAccent : theme.muted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .disabled(!canRunRemoteOperation)
    }

    private var canCommit: Bool {
        !stagedChanges.isEmpty && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canRunRemoteOperation: Bool {
        store.gitSummary?.hasRemote == true && !store.isGitOperationRunning
    }
}

private struct GitGraphIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let lineWidth = max(1.5, size * 0.11)
            let radius = size * 0.16
            let top = CGPoint(x: size * 0.24, y: size * 0.16)
            let middle = CGPoint(x: size * 0.24, y: size * 0.52)
            let bottom = CGPoint(x: size * 0.24, y: size * 0.86)
            let branch = CGPoint(x: size * 0.74, y: size * 0.34)

            ZStack {
                Path { path in
                    path.move(to: top)
                    path.addLine(to: bottom)
                    path.move(to: middle)
                    path.addLine(to: branch)
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                Circle().stroke(lineWidth: lineWidth).frame(width: radius * 2, height: radius * 2).position(top)
                Circle().stroke(lineWidth: lineWidth).frame(width: radius * 2, height: radius * 2).position(bottom)
                Circle().stroke(lineWidth: lineWidth).frame(width: radius * 2, height: radius * 2).position(branch)
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct SourceControlSectionAction {
    let symbol: String
    let label: String
    let action: () -> Void
}

private struct SourceControlSection<Content: View>: View {
    @Environment(\.airCodeTheme) private var theme
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    let trailingAction: SourceControlSectionAction?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .frame(width: 18, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.muted)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.muted)
                Spacer()
                if let trailingAction {
                    Button(action: trailingAction.action) {
                        Image(systemName: trailingAction.symbol)
                            .font(.caption2.weight(.bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel(trailingAction.label)
                }
            }
            if isExpanded {
                content
            }
        }
    }
}

private struct SourceControlChangeRow: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let change: GitChange
    let placement: SourceControlPlacement

    var body: some View {
        HStack(spacing: 7) {
            Text(kind.shortLabel)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(kind.color(theme))
                .frame(width: 18)
            HStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(kind.color(theme))
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.caption)
                        .lineLimit(1)
                    if isDirectoryEntry {
                        Text(change.path)
                            .font(.caption2)
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Task { await store.loadDiff(path: change.path) }
            }

            Button {
                Task {
                    switch placement {
                    case .staged:
                        await store.unstage(path: change.path)
                    case .unstaged:
                        await store.stage(path: change.path)
                    }
                }
            } label: {
                Image(systemName: placement == .staged ? "minus" : "plus")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(placement == .staged ? theme.muted : theme.accent)
            .accessibilityLabel(placement == .staged ? "Unstage \(change.path)" : "Stage \(change.path)")

            Button {
                Task { await store.revert(path: change.path) }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.muted)
            .accessibilityLabel("Discard \(change.path)")
        }
        .padding(.horizontal, 7)
        .frame(height: isDirectoryEntry ? 40 : 28)
        .background(theme.elevated.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border.opacity(0.7)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button("Open Diff") { Task { await store.loadDiff(path: change.path) } }
            Button(placement == .staged ? "Unstage" : "Stage") {
                Task {
                    if placement == .staged {
                        await store.unstage(path: change.path)
                    } else {
                        await store.stage(path: change.path)
                    }
                }
            }
            Button("Discard Changes", role: .destructive) {
                Task { await store.revert(path: change.path) }
            }
        }
    }

    private var displayName: String {
        (change.path as NSString).lastPathComponent.isEmpty ? change.path : (change.path as NSString).lastPathComponent
    }

    private var isDirectoryEntry: Bool {
        change.path.hasSuffix("/")
    }

    private var kind: SourceControlChangeKind {
        SourceControlChangeKind(status: change.status)
    }
}

private enum SourceControlPlacement {
    case staged
    case unstaged
}

private enum SourceControlChangeKind {
    case added
    case modified
    case deleted
    case renamed
    case conflicted
    case unknown

    init(status: String) {
        let value = status.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("U") {
            self = .conflicted
        } else if value.contains("D") {
            self = .deleted
        } else if value.contains("R") {
            self = .renamed
        } else if value.contains("A") || value.contains("??") {
            self = .added
        } else if value.contains("M") {
            self = .modified
        } else {
            self = .unknown
        }
    }

    var shortLabel: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .conflicted: return "!"
        case .unknown: return "?"
        }
    }

    var symbol: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified: return "circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .conflicted: return "exclamationmark.triangle.fill"
        case .unknown: return "circle.dashed"
        }
    }

    func color(_ theme: AirCodeTheme) -> Color {
        switch self {
        case .added: return theme.green
        case .modified: return theme.yellow
        case .deleted: return theme.red
        case .renamed: return theme.blue
        case .conflicted: return theme.orange
        case .unknown: return theme.muted
        }
    }
}

private struct ProjectSearchView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(theme.muted)
                TextField("Search files", text: $store.searchQuery)
                    .font(.caption)
                    .onSubmit {
                        Task { await store.searchFiles() }
                    }
                if store.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(theme.editor)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 6) {
                Button {
                    Task { await store.searchFiles() }
                } label: {
                    Label("Search", systemImage: "arrow.right.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .background(theme.accent.opacity(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.12 : 0.22))
                .foregroundStyle(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.muted : theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.searchQuery = ""
                    store.searchResults = []
                    store.searchMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(theme.elevated)
                .foregroundStyle(theme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Clear Search")
            }

            if let message = store.searchMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(message.hasPrefix("HTTP") ? theme.red : theme.muted)
                    .lineLimit(2)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(store.searchResults) { result in
                        SearchResultRow(result: result)
                            .environmentObject(store)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
    }
}

private struct SearchResultRow: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let result: SearchResult

    var body: some View {
        Button {
            Task { await store.openSearchResult(result) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(theme.accent)
                    Text(result.path)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(result.lineNumber):\(result.column)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.muted)
                }
                Text(result.line.trimmingCharacters(in: .whitespaces))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.elevated.opacity(store.selectedFilePath == result.path ? 1 : 0.65))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(store.selectedFilePath == result.path ? theme.accent.opacity(0.5) : theme.border.opacity(0.55)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TreeNodeView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let entry: TreeEntry
    let depth: Int

    private var isExpanded: Bool {
        entry.isDirectory && store.treeEntries[entry.path] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await store.open(entry: entry) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: entry.isDirectory ? (isExpanded ? "chevron.down" : "chevron.right") : " ")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 10)
                    FileTreeIcon(entry: entry, isExpanded: isExpanded)
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.leading, CGFloat(depth * 12) + 6)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .contentShape(Rectangle())
                .background(store.selectedFilePath == entry.path ? theme.elevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            if entry.isDirectory, let children = store.treeEntries[entry.path] {
                ForEach(children) { child in
                    TreeNodeView(entry: child, depth: depth + 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FileTreeIcon: View {
    @Environment(\.airCodeTheme) private var theme
    let entry: TreeEntry
    let isExpanded: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .frame(width: 16)
    }

    private var symbol: String {
        if entry.isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        switch fileKind {
        case .swift: return "swift"
        case .web: return "chevron.left.forwardslash.chevron.right"
        case .script: return "terminal"
        case .markdown: return "doc.richtext"
        case .json: return "curlybraces"
        case .config: return "gearshape"
        case .image: return "photo"
        case .media: return "play.rectangle"
        case .archive: return "archivebox"
        case .database: return "cylinder"
        case .git: return "arrow.triangle.branch"
        case .test: return "checkmark.seal"
        case .text: return "doc.text"
        }
    }

    private var color: Color {
        if entry.isDirectory { return theme.accent }
        switch fileKind {
        case .swift: return theme.orange
        case .web: return theme.blue
        case .script: return theme.green
        case .markdown: return theme.accent
        case .json: return theme.yellow
        case .config: return theme.muted
        case .image: return theme.blue
        case .media: return theme.red
        case .archive: return theme.orange
        case .database: return theme.green
        case .git: return theme.orange
        case .test: return theme.green
        case .text: return theme.muted
        }
    }

    private var fileKind: FileTreeIconKind {
        FileTreeIconKind(name: entry.name)
    }
}

private enum FileTreeIconKind {
    case swift
    case web
    case script
    case markdown
    case json
    case config
    case image
    case media
    case archive
    case database
    case git
    case test
    case text

    init(name: String) {
        let lower = name.lowercased()
        let ext = lower.split(separator: ".").last.map(String.init) ?? ""
        if lower == ".gitignore" || lower == ".gitattributes" || lower == ".gitmodules" {
            self = .git
        } else if lower.contains(".test.") || lower.contains(".spec.") || lower.hasSuffix("_test.go") {
            self = .test
        } else if ext == "swift" {
            self = .swift
        } else if ["ts", "tsx", "js", "jsx", "vue", "html", "css", "scss", "sass", "mjs", "cjs"].contains(ext) {
            self = .web
        } else if ["sh", "bash", "zsh", "fish", "py", "rb", "pl"].contains(ext) {
            self = .script
        } else if ["md", "markdown", "mdx"].contains(ext) {
            self = .markdown
        } else if ["json", "jsonc", "lock"].contains(ext) || lower == "package-lock.json" {
            self = .json
        } else if ["toml", "yaml", "yml", "ini", "env", "plist", "config"].contains(ext) || lower.hasPrefix(".env") {
            self = .config
        } else if ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "ico"].contains(ext) {
            self = .image
        } else if ["mp4", "mov", "mp3", "wav", "m4a"].contains(ext) {
            self = .media
        } else if ["zip", "gz", "tgz", "tar", "xz", "7z"].contains(ext) {
            self = .archive
        } else if ["db", "sqlite", "sqlite3", "sql"].contains(ext) {
            self = .database
        } else {
            self = .text
        }
    }
}

struct RemoteFolderPickerView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRootID: String?
    @State private var selectedPath = "."
    @State private var isNewFolderPresented = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            if store.workspaceRoots.isEmpty {
                ContentUnavailableView("No Remote Roots", systemImage: "externaldrive.badge.xmark")
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.panel)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        rootRow
                        ForEach((store.workspaceTreeEntries["."] ?? []).filter(\.isDirectory)) { entry in
                            RemoteFolderPickerNode(entry: entry, depth: 0, selectedPath: $selectedPath)
                                .environmentObject(store)
                        }
                    }
                    .padding(10)
                }
                .background(theme.panel)
            }
            Divider().overlay(theme.border)
            footer
        }
        .frame(minWidth: 440, minHeight: 520)
        .background(theme.panel)
        .foregroundStyle(theme.foreground)
        .task {
            if selectedRootID == nil {
                selectedRootID = store.selectedWorkspaceRootID ?? store.workspaceRoots.first?.id
            }
            if let selectedRootID {
                await store.loadWorkspaceTree(rootId: selectedRootID, path: ".")
            }
        }
        .alert("New Folder", isPresented: $isNewFolderPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                createAndOpenFolder()
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text("Create under \(displayPath(selectedPath)) and open it.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(theme.accent)
            Text("Open Folder")
                .font(.headline)
            Spacer()
            if store.workspaceRoots.count > 1 {
                Menu {
                    ForEach(store.workspaceRoots) { root in
                        Button {
                            selectRoot(root.id)
                        } label: {
                            Label(root.name, systemImage: root.id == selectedRootID ? "checkmark" : (root.pinned ? "star.fill" : "externaldrive"))
                        }
                    }
                } label: {
                    Label(selectedRoot?.name ?? "Root", systemImage: "externaldrive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(theme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.button)
            } else if let root = selectedRoot {
                Text(root.name)
                    .font(.caption)
                    .foregroundStyle(theme.muted)
            }
            if let root = selectedRoot {
                Button {
                    Task { await store.toggleWorkspaceRootPinned(root) }
                } label: {
                    Image(systemName: root.pinned ? "star.fill" : "star")
                        .frame(width: 28, height: 28)
                        .background(theme.elevated)
                        .foregroundStyle(root.pinned ? theme.yellow : theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(root.pinned ? "Unpin Workspace Root" : "Pin Workspace Root")
            }
            Button {
                newFolderName = ""
                isNewFolderPresented = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .frame(width: 28, height: 28)
                    .background(theme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(selectedRootID == nil)
            .accessibilityLabel("Create New Folder")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(displayPath(selectedPath))
                .font(.caption)
                .foregroundStyle(theme.muted)
                .lineLimit(1)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.borderless)
            Button {
                Task {
                    await store.openWorkspaceFolder(rootId: selectedRootID, path: selectedPath)
                    dismiss()
                }
            } label: {
                Label("Open", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(selectedRootID == nil)
        }
        .padding(12)
    }

    private var rootRow: some View {
        Button {
            selectedPath = "."
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(theme.accent)
                Text(selectedRoot?.name ?? "Workspace Root")
                    .font(.caption)
                    .lineLimit(1)
                if selectedRoot?.pinned == true {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.yellow)
                }
                Spacer()
                if selectedPath == "." {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selectedPath == "." ? theme.elevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var selectedRoot: WorkspaceRootSummary? {
        store.workspaceRoots.first { $0.id == selectedRootID }
    }

    private func selectRoot(_ rootID: String) {
        selectedRootID = rootID
        selectedPath = "."
        Task { await store.loadWorkspaceTree(rootId: rootID, path: ".") }
    }

    private func displayPath(_ path: String) -> String {
        path == "." ? selectedRoot?.name ?? "Workspace Root" : path
    }

    private func createAndOpenFolder() {
        let name = newFolderName
        Task {
            let didOpen = await store.createAndOpenWorkspaceFolder(rootId: selectedRootID, parentPath: selectedPath, name: name)
            if didOpen {
                dismiss()
            }
            newFolderName = ""
        }
    }
}

private struct RemoteFolderPickerNode: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let entry: TreeEntry
    let depth: Int
    @Binding var selectedPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    Task { await store.toggleWorkspaceTree(path: entry.path) }
                } label: {
                    Image(systemName: store.workspaceTreeEntries[entry.path] == nil ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .frame(width: 14, height: 26)
                        .foregroundStyle(theme.muted)
                }
                .buttonStyle(.plain)

                Button {
                    selectedPath = entry.path
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                        Text(entry.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if selectedPath == entry.path {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth * 14))
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selectedPath == entry.path ? theme.elevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let children = store.workspaceTreeEntries[entry.path] {
                ForEach(children.filter(\.isDirectory)) { child in
                    RemoteFolderPickerNode(entry: child, depth: depth + 1, selectedPath: $selectedPath)
                }
            }
        }
    }
}
