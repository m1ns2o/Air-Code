@preconcurrency import CodeEditorView
import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct EditorPaneView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var isFindVisible = false
    @State private var isReplaceVisible = false
    @State private var findQuery = ""
    @State private var replaceText = ""
    @State private var isFindCaseInsensitive = false
    @State private var currentMatchIndex: Int?
    @State private var selectionRequest: EditorSelectionRequest?
    @State private var isHoverVisible = false
    @State private var editorCaretRect: CGRect?
    @State private var isRenameVisible = false
    @State private var renameText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider().overlay(theme.border)
            if store.isDiffViewerVisible {
                SideBySideDiffView(path: store.selectedDiffPath ?? "Diff", diff: store.selectedDiff)
                    .environmentObject(store)
            } else if let conflict = store.selectedFileConflict {
                ConflictResolutionView(conflict: conflict)
                    .environmentObject(store)
            } else if let selected = bindingForSelectedFile {
                editorSurface(selected)
            } else if store.selectedProject == nil {
                RecentProjectsView()
                    .environmentObject(store)
            } else {
                ContentUnavailableView("No File", systemImage: "doc.text", description: Text("Open a file from the folder tree."))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.editor)
            }
        }
        .background(theme.editor)
        .overlay(alignment: .topLeading) {
            editorKeyCommands
        }
        .onChange(of: store.selectedFilePath) { _, _ in
            currentMatchIndex = nil
            selectionRequest = nil
        }
        .alert("Rename Symbol", isPresented: $isRenameVisible) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let nextName = renameText
                Task { await store.renameSymbol(to: nextName) }
            }
        } message: {
            Text("Rename the symbol at the current cursor position.")
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(store.openFiles) { file in
                    Button {
                        store.selectOpenFile(path: file.path)
                    } label: {
                        HStack(spacing: 6) {
                            Text((file.path as NSString).lastPathComponent)
                                .font(.caption)
                            if file.isDirty {
                                Circle()
                                    .fill(theme.yellow)
                                    .frame(width: 6, height: 6)
                            }
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .onTapGesture {
                                    store.close(path: file.path)
                                }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(store.selectedFilePath == file.path ? theme.elevated : theme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(theme.panel)
    }

    private var bindingForSelectedFile: Binding<String>? {
        guard let path = store.selectedFilePath,
              let index = store.openFiles.firstIndex(where: { $0.path == path }) else { return nil }
        return Binding(
            get: { store.openFiles[index].content },
            set: { store.updateSelectedFileContent($0) }
        )
    }

    private func editorSurface(_ selected: Binding<String>) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                NativeCodeEditor(
                    text: selected,
                    path: store.selectedFilePath ?? "",
                    selectionRequest: selectionRequest ?? store.editorSelectionRequest,
                    diagnostics: store.diagnosticsForSelectedFile()
                ) { snapshot in
                    store.updateEditorContext(snapshot)
                } onCaretRectChange: { rect in
                    editorCaretRect = rect
                } onCompletionCommand: { command in
                    switch command {
                    case .accept:
                        return store.acceptSelectedLSPCompletion()
                    }
                }
                .background(theme.editor)

                if store.isLSPCompletionVisible, editorCaretRect != nil {
                    completionPopup
                        .frame(width: completionPopupSize.width, height: completionPopupSize.height)
                        .position(completionPopupPosition(in: proxy.size))
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }

                if isHoverVisible, let hover = store.lspHover {
                    hoverPopover(hover)
                        .frame(width: 360, alignment: .topLeading)
                        .position(hoverPopoverPosition(in: proxy.size))
                        .transition(.opacity)
                }

                if isFindVisible {
                    EditorFindBar(
                        findQuery: $findQuery,
                        replaceText: $replaceText,
                        isReplaceVisible: $isReplaceVisible,
                        isCaseInsensitive: $isFindCaseInsensitive,
                        matchLabel: matchLabel,
                        canReplace: !findQuery.isEmpty && !matches.isEmpty,
                        onPrevious: { selectMatch(.backward) },
                        onNext: { selectMatch(.forward) },
                        onReplace: replaceCurrentMatch,
                        onReplaceAll: replaceAllMatches,
                        onClose: closeFind
                    )
                    .padding(10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: store.selectedFilePath) { _, _ in
                editorCaretRect = nil
            }
            .onChange(of: store.isLSPCompletionVisible) { _, visible in
                if !visible {
                    editorCaretRect = nil
                }
            }
            .onChange(of: selected.wrappedValue) { _, _ in
                reconcileFindSelectionAfterTextChange()
            }
            .onChange(of: findQuery) { _, _ in
                currentMatchIndex = nil
                selectMatch(.forward, focusEditor: false)
            }
            .onChange(of: isFindCaseInsensitive) { _, _ in
                currentMatchIndex = nil
                selectMatch(.forward, focusEditor: false)
            }
        }
    }

    private var completionPopupSize: CGSize {
        CGSize(width: 340, height: min(CGFloat(max(store.lspCompletionItems.count, 1)) * 44 + 42, 280))
    }

    private func completionPopupPosition(in size: CGSize) -> CGPoint {
        guard let rect = editorCaretRect else {
            return CGPoint(
                x: completionPopupSize.width / 2 + 8,
                y: completionPopupSize.height / 2 + 8
            )
        }
        let popupSize = completionPopupSize
        let preferredX = rect.minX + popupSize.width / 2
        let lowerX = popupSize.width / 2 + 8
        let upperX = max(lowerX, size.width - popupSize.width / 2 - 8)
        let x = min(max(preferredX, lowerX), upperX)
        let belowY = rect.maxY + 8 + popupSize.height / 2
        let aboveY = rect.minY - 8 - popupSize.height / 2
        let y: CGFloat
        if belowY + popupSize.height / 2 <= size.height - 8 {
            y = belowY
        } else if aboveY - popupSize.height / 2 >= 8 {
            y = aboveY
        } else {
            y = min(max(belowY, popupSize.height / 2 + 8), max(popupSize.height / 2 + 8, size.height - popupSize.height / 2 - 8))
        }
        return CGPoint(x: x, y: y)
    }

    private func hoverPopoverPosition(in size: CGSize) -> CGPoint {
        let width: CGFloat = 360
        let height: CGFloat = 190
        if let rect = editorCaretRect {
            return CGPoint(
                x: min(max(rect.minX + width / 2, width / 2 + 8), max(width / 2 + 8, size.width - width / 2 - 8)),
                y: min(max(rect.maxY + height / 2 + 12, height / 2 + 8), max(height / 2 + 8, size.height - height / 2 - 8))
            )
        }
        return CGPoint(x: max(width / 2 + 8, size.width - width / 2 - 12), y: height / 2 + 12)
    }

    private var editorKeyCommands: some View {
        VStack {
            Button("Save File") {
                Task { await store.saveSelectedFile() }
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button("Find") {
                openFind(replace: false)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Complete") {
                Task { await store.requestLSPCompletion() }
            }
            .keyboardShortcut(.space, modifiers: [.control])

            if store.isLSPCompletionVisible {
                Button("Completion Next") {
                    store.moveLSPCompletionSelection(1)
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Button("Completion Previous") {
                    store.moveLSPCompletionSelection(-1)
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("Accept Completion") {
                    _ = store.acceptSelectedLSPCompletion()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Dismiss Completion") {
                    store.hideLSPCompletion()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Button("Go to Definition") {
                Task { await store.goToLSPDefinition() }
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button("Hover") {
                Task {
                    await store.requestLSPHover()
                    isHoverVisible = store.lspHover != nil
                }
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Rename Symbol") {
                renameText = ""
                isRenameVisible = true
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Replace") {
                openFind(replace: true)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button("Find Next") {
                selectMatch(.forward)
            }
            .keyboardShortcut("g", modifiers: [.command])

            Button("Find Previous") {
                selectMatch(.backward)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button("Close Editor Tab") {
                if let path = store.selectedFilePath {
                    store.close(path: path)
                    if store.selectedFilePath == nil {
                        closeFind()
                    }
                }
            }
            .keyboardShortcut("w", modifiers: [.command])

            Button("Comment Selection") {
                sendCodeEditorAction(#selector(CodeEditorActions.commentSelection(_:)))
            }
            .keyboardShortcut("/", modifiers: [.command])

            Button("Shift Left") {
                sendCodeEditorAction(#selector(CodeEditorActions.shiftLeft(_:)))
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("Shift Right") {
                sendCodeEditorAction(#selector(CodeEditorActions.shiftRight(_:)))
            }
            .keyboardShortcut("]", modifiers: [.command])

            Button("Re-Indent") {
                sendCodeEditorAction(#selector(CodeEditorActions.reindent(_:)))
            }
            .keyboardShortcut("i", modifiers: [.control])
        }
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .accessibilityHidden(true)
    }

    private var currentText: String {
        bindingForSelectedFile?.wrappedValue ?? ""
    }

    private var completionPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Suggestions", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.foreground)
                Spacer()
                Button {
                    store.hideLSPCompletion()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(store.lspCompletionItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            store.applyLSPCompletion(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "curlybraces")
                                    .font(.caption)
                                    .foregroundStyle(theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.label)
                                        .font(.caption.monospaced().weight(.semibold))
                                        .foregroundStyle(theme.foreground)
                                        .lineLimit(1)
                                    if let detail = item.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.caption2)
                                            .foregroundStyle(theme.muted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(index == store.selectedLSPCompletionIndex ? theme.accent.opacity(0.16) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    private func hoverPopover(_ hover: LSPHoverResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Hover", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    isHoverVisible = false
                    store.clearLSPHover()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            Text(hover.contents)
                .font(.caption.monospaced())
                .foregroundStyle(theme.foreground)
                .textSelection(.enabled)
                .lineLimit(10)
        }
        .padding(10)
        .frame(width: 360, alignment: .leading)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var isFindCaseSensitive: Bool {
        !isFindCaseInsensitive
    }

    private var matches: [NSRange] {
        EditorFindEngine.matches(in: currentText, query: findQuery, caseSensitive: isFindCaseSensitive)
    }

    private var matchLabel: String {
        guard !findQuery.isEmpty else { return "0/0" }
        let count = matches.count
        guard count > 0 else { return "0/0" }
        let displayIndex = min(max((currentMatchIndex ?? 0) + 1, 1), count)
        return "\(displayIndex)/\(count)"
    }

    private func openFind(replace: Bool) {
        guard store.selectedFilePath != nil else { return }
        isFindVisible = true
        isReplaceVisible = replace || isReplaceVisible
        if !findQuery.isEmpty {
            selectMatch(.forward, focusEditor: false)
        }
    }

    private func closeFind() {
        isFindVisible = false
        isReplaceVisible = false
        currentMatchIndex = nil
        selectionRequest = nil
    }

    private func selectMatch(_ direction: SearchDirection, focusEditor: Bool = true) {
        let matchRanges = matches
        guard let index = EditorFindEngine.nextIndex(currentIndex: currentMatchIndex, matchCount: matchRanges.count, direction: direction) else {
            currentMatchIndex = nil
            return
        }
        currentMatchIndex = index
        selectionRequest = EditorSelectionRequest(range: matchRanges[index], shouldFocusEditor: focusEditor)
    }

    private func replaceCurrentMatch() {
        guard let binding = bindingForSelectedFile else { return }
        let matchRanges = matches
        guard !matchRanges.isEmpty else { return }
        let index = min(max(currentMatchIndex ?? 0, 0), matchRanges.count - 1)
        guard let updated = EditorFindEngine.replace(in: binding.wrappedValue, range: matchRanges[index], with: replaceText) else { return }
        binding.wrappedValue = updated
        let updatedMatches = EditorFindEngine.matches(in: updated, query: findQuery, caseSensitive: isFindCaseSensitive)
        guard !updatedMatches.isEmpty else {
            currentMatchIndex = nil
            selectionRequest = nil
            return
        }
        currentMatchIndex = min(index, updatedMatches.count - 1)
        selectionRequest = EditorSelectionRequest(range: updatedMatches[currentMatchIndex ?? 0])
    }

    private func replaceAllMatches() {
        guard let binding = bindingForSelectedFile else { return }
        let result = EditorFindEngine.replaceAll(in: binding.wrappedValue, query: findQuery, replacement: replaceText, caseSensitive: isFindCaseSensitive)
        guard result.count > 0 else { return }
        binding.wrappedValue = result.text
        currentMatchIndex = nil
        selectionRequest = nil
    }

    private func reconcileFindSelectionAfterTextChange() {
        guard isFindVisible, !findQuery.isEmpty else { return }
        let matchRanges = matches
        guard !matchRanges.isEmpty else {
            currentMatchIndex = nil
            selectionRequest = nil
            return
        }
        if let currentMatchIndex, matchRanges.indices.contains(currentMatchIndex) {
            return
        }
        currentMatchIndex = 0
        selectionRequest = EditorSelectionRequest(range: matchRanges[0])
    }

    private func sendCodeEditorAction(_ selector: Selector) {
        #if os(macOS)
        NSApplication.shared.sendAction(selector, to: nil, from: nil)
        #elseif os(iOS) || os(visionOS)
        UIApplication.shared.sendAction(selector, to: nil, from: nil, for: nil)
        #endif
    }
}

private struct EditorFindBar: View {
    @Binding var findQuery: String
    @Binding var replaceText: String
    @Binding var isReplaceVisible: Bool
    @Binding var isCaseInsensitive: Bool
    let matchLabel: String
    let canReplace: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @Environment(\.airCodeTheme) private var theme
    @FocusState private var isFindFocused: Bool
    @FocusState private var isReplaceFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                toggleReplaceButton

                findField

                Text(matchLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.muted)
                    .frame(width: 44, alignment: .trailing)

                iconOnlyButton(systemImage: "chevron.up", help: "Previous Match", disabled: findQuery.isEmpty, action: onPrevious)
                iconOnlyButton(systemImage: "chevron.down", help: "Next Match", disabled: findQuery.isEmpty, action: onNext)
                iconTextButton("Close", systemImage: "xmark", help: "Close Find", action: onClose)
            }

            if isReplaceVisible {
                HStack(spacing: 8) {
                    replaceAlignmentSpacer

                    replaceField

                    Spacer().frame(width: 44)
                    iconTextButton("Replace", systemImage: "arrow.triangle.2.circlepath", help: "Replace Current Match", disabled: !canReplace, action: onReplace)
                    iconTextButton("All", systemImage: "arrow.triangle.2.circlepath.circle", help: "Replace All Matches", disabled: !canReplace, action: onReplaceAll)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(8)
        .frame(width: 482, alignment: .leading)
        .background(theme.elevated)
        .foregroundStyle(theme.foreground)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(theme.isLight ? 0.12 : 0.24), radius: 12, y: 8)
        .onAppear {
            isFindFocused = true
        }
    }

    private var toggleReplaceButton: some View {
        Button {
            isReplaceVisible.toggle()
            if isReplaceVisible {
                isReplaceFocused = true
            }
        } label: {
            Image(systemName: isReplaceVisible ? "chevron.compact.down" : "chevron.compact.right")
                .font(.caption.weight(.medium))
                .frame(width: 18, height: 28)
        }
        .buttonStyle(.plain)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(isReplaceVisible ? "Hide Replace" : "Show Replace")
    }

    private var replaceAlignmentSpacer: some View {
        Spacer()
            .frame(width: 18)
    }

    private var findField: some View {
        HStack(spacing: 4) {
            TextField("Find", text: $findQuery)
                .textFieldStyle(.plain)
                .focused($isFindFocused)
                .onSubmit(onNext)
                .font(.system(size: 13, design: .monospaced))
                .padding(.leading, 8)
                .frame(height: 28)

            Button {
                isCaseInsensitive.toggle()
            } label: {
                Text("Aa")
                    .font(.caption2.weight(.semibold))
                    .monospaced()
                    .frame(width: 25, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCaseInsensitive ? theme.panel : theme.foreground)
            .background(isCaseInsensitive ? theme.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help(isCaseInsensitive ? "Case insensitive: On" : "Case insensitive: Off")
            .padding(.trailing, 3)
        }
        .frame(width: 210, height: 28)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var replaceField: some View {
        TextField("Replace", text: $replaceText)
            .textFieldStyle(.plain)
            .focused($isReplaceFocused)
            .onSubmit(onReplace)
            .font(.system(size: 13, design: .monospaced))
            .padding(.horizontal, 8)
            .frame(width: 210, height: 28)
            .background(theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func iconTextButton(
        _ title: String,
        systemImage: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? theme.muted.opacity(0.45) : theme.foreground)
        .background(theme.panel.opacity(disabled ? 0.55 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .disabled(disabled)
        .help(help)
    }

    private func iconOnlyButton(
        systemImage: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? theme.muted.opacity(0.45) : theme.foreground)
        .background(theme.panel.opacity(disabled ? 0.55 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .disabled(disabled)
        .help(help)
    }
}

private struct RecentProjectsView: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    @State private var isOpenFolderPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Recent")
                        .font(.title2.weight(.semibold))
                    Text("Choose a remote folder from this server or open a new one.")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Button {
                    isOpenFolderPresented = true
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }

            if store.recentProjects.isEmpty {
                ContentUnavailableView("No Recent Projects", systemImage: "clock", description: Text("Open a remote folder to pin it here for the next launch."))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(store.recentProjects) { recent in
                            RecentProjectRow(recent: recent)
                                .environmentObject(store)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.editor)
        .sheet(isPresented: $isOpenFolderPresented) {
            RemoteFolderPickerView()
                .environmentObject(store)
                .environment(\.airCodeTheme, theme)
        }
    }
}

private struct RecentProjectRow: View {
    @EnvironmentObject private var store: AirCodeStore
    @Environment(\.airCodeTheme) private var theme
    let recent: RecentProjectSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(theme.accent)
                .frame(width: 20)
            Button {
                Task { await store.openRecentProject(recent) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(recent.path == "." ? recent.rootId : "\(recent.rootId) / \(recent.path)")
                        .font(.caption)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                Task { await store.toggleRecentProjectPinned(recent) }
            } label: {
                Image(systemName: recent.pinned ? "star.fill" : "star")
                    .font(.caption)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(recent.pinned ? theme.yellow : theme.muted)
            .accessibilityLabel(recent.pinned ? "Unpin \(recent.name)" : "Pin \(recent.name)")
            Button {
                Task { await store.forgetRecentProject(recent) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.muted)
            .accessibilityLabel("Remove \(recent.name) from recent projects")
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
