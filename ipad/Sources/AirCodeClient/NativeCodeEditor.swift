import Foundation
import SwiftUI
import CodeEditorView
import LanguageSupport

public struct EditorSelectionRequest: Equatable {
    public let id: UUID
    public let range: NSRange
    public let shouldFocusEditor: Bool

    public init(range: NSRange, shouldFocusEditor: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.range = range
        self.shouldFocusEditor = shouldFocusEditor
    }
}

public struct NativeCodeEditor: View {
    @Binding var text: String
    let path: String
    let selectionRequest: EditorSelectionRequest?
    let diagnostics: [LSPDiagnostic]
    let onContextChange: (EditorContextSnapshot) -> Void
    @Environment(\.airCodeTheme) private var theme
    @State private var position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []
    @State private var contextReportTask: Task<Void, Never>?

    public init(
        text: Binding<String>,
        path: String,
        selectionRequest: EditorSelectionRequest? = nil,
        diagnostics: [LSPDiagnostic] = [],
        onContextChange: @escaping (EditorContextSnapshot) -> Void = { _ in }
    ) {
        self._text = text
        self.path = path
        self.selectionRequest = selectionRequest
        self.diagnostics = diagnostics
        self.onContextChange = onContextChange
    }

    public var body: some View {
        CodeEditor(text: $text, position: $position, messages: $messages, language: language)
            .environment(\.codeEditorTheme, theme.codeEditorTheme)
            .environment(\.codeEditorLayoutConfiguration, CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: false))
            .tint(theme.cursor)
            .background(theme.editor)
            #if os(iOS) || os(visionOS)
            .overlay {
                ZStack {
                    CodeEditorCursorTintSynchronizer(cursorHex: theme.cursorHex)
                    CodeEditorSelectionSynchronizer(selectionRequest: selectionRequest)
                }
                .allowsHitTesting(false)
            }
            #endif
            .onAppear {
                messages = editorMessages(from: diagnostics)
                scheduleContextReport(position, delayNanoseconds: 0)
            }
            .onDisappear {
                contextReportTask?.cancel()
                contextReportTask = nil
            }
            .onChange(of: position) { _, newPosition in
                scheduleContextReport(newPosition, delayNanoseconds: 90_000_000)
            }
            .onChange(of: text) { _, _ in
                scheduleContextReport(position, delayNanoseconds: 260_000_000)
            }
            .onChange(of: path) { _, _ in
                messages = editorMessages(from: diagnostics)
                scheduleContextReport(position, delayNanoseconds: 0)
            }
            .onChange(of: diagnostics) { _, newDiagnostics in
                messages = editorMessages(from: newDiagnostics)
            }
            .onChange(of: selectionRequest) { _, request in
                guard let request else { return }
                position = CodeEditor.Position(selections: [request.range], verticalScrollPosition: position.verticalScrollPosition)
                scheduleContextReport(position, delayNanoseconds: 0)
        }
    }

    private func editorMessages(from diagnostics: [LSPDiagnostic]) -> Set<TextLocated<Message>> {
        Set(diagnostics.map { diagnostic in
            TextLocated(
                location: TextLocation(
                    zeroBasedLine: max(0, diagnostic.range.start.line),
                    column: max(0, diagnostic.range.start.character)
                ),
                entity: Message(
                    category: messageCategory(for: diagnostic),
                    length: max(1, diagnostic.range.end.character - diagnostic.range.start.character),
                    summary: diagnostic.message,
                    description: AttributedString(diagnostic.source ?? diagnostic.severityTitle)
                )
            )
        })
    }

    private func messageCategory(for diagnostic: LSPDiagnostic) -> Message.Category {
        switch diagnostic.severity {
        case 1:
            return .error
        case 2:
            return .warning
        default:
            return .informational
        }
    }

    private var language: LanguageConfiguration {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return .swift()
        case "go": return .go()
        case "py": return .python()
        case "js", "jsx", "mjs", "cjs": return .javascript()
        case "ts", "tsx": return .typescript()
        case "vue": return .vue()
        case "sql", "sqlite": return .sqlite()
        default: return .none
        }
    }

    private func scheduleContextReport(_ currentPosition: CodeEditor.Position, delayNanoseconds: UInt64) {
        contextReportTask?.cancel()
        let currentPath = path
        let currentText = text
        let selection = currentPosition.selections.first ?? .zero
        contextReportTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            let snapshot = EditorContextSnapshot.make(path: currentPath, text: currentText, selection: selection)
            guard !Task.isCancelled else { return }
            onContextChange(snapshot)
        }
    }
}

#if os(iOS) || os(visionOS)
private struct CodeEditorCursorTintSynchronizer: UIViewRepresentable {
    let cursorHex: UInt32

    final class Coordinator {
        var lastAppliedHex: UInt32?
        var isScheduled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        synchronize(from: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        synchronize(from: uiView, coordinator: context.coordinator)
    }

    private func synchronize(from markerView: UIView, coordinator: Coordinator) {
        guard coordinator.lastAppliedHex != cursorHex, !coordinator.isScheduled else { return }
        coordinator.isScheduled = true
        DispatchQueue.main.async {
            coordinator.isScheduled = false
            let cursorColor = UIColor(hex: cursorHex)
            let searchRoot = nearestSearchRoot(from: markerView)
            if applyCursorTint(in: searchRoot, cursorColor: cursorColor) {
                coordinator.lastAppliedHex = cursorHex
                return
            }
            if let window = markerView.window {
                if applyCursorTint(in: window, cursorColor: cursorColor) {
                    coordinator.lastAppliedHex = cursorHex
                }
            }
        }
    }

    private func nearestSearchRoot(from view: UIView) -> UIView {
        var root = view
        for _ in 0..<8 {
            guard let superview = root.superview else { break }
            root = superview
        }
        return root
    }

    @discardableResult
    private func applyCursorTint(in view: UIView, cursorColor: UIColor) -> Bool {
        var didApply = false
        let typeName = NSStringFromClass(type(of: view))
        if let textView = view as? UITextView, typeName.contains("CodeView") {
            textView.tintColor = cursorColor
            didApply = true
        }
        for subview in view.subviews {
            didApply = applyCursorTint(in: subview, cursorColor: cursorColor) || didApply
        }
        return didApply
    }
}

private struct CodeEditorSelectionSynchronizer: UIViewRepresentable {
    let selectionRequest: EditorSelectionRequest?

    final class Coordinator {
        var lastAppliedID: UUID?
        var isScheduled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let selectionRequest,
              context.coordinator.lastAppliedID != selectionRequest.id,
              !context.coordinator.isScheduled else { return }
        context.coordinator.isScheduled = true
        DispatchQueue.main.async {
            context.coordinator.isScheduled = false
            guard let textView = findCodeTextView(from: uiView) else { return }
            let textLength = (textView.text ?? "").utf16.count
            let lower = min(max(0, selectionRequest.range.location), textLength)
            let upper = min(max(lower, selectionRequest.range.location + selectionRequest.range.length), textLength)
            let range = NSRange(location: lower, length: upper - lower)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
            if selectionRequest.shouldFocusEditor {
                textView.becomeFirstResponder()
            }
            context.coordinator.lastAppliedID = selectionRequest.id
        }
    }

    private func findCodeTextView(from markerView: UIView) -> UITextView? {
        let searchRoot = nearestSearchRoot(from: markerView)
        if let textView = firstCodeTextView(in: searchRoot) {
            return textView
        }
        guard let window = markerView.window else { return nil }
        return firstCodeTextView(in: window)
    }

    private func nearestSearchRoot(from view: UIView) -> UIView {
        var root = view
        for _ in 0..<8 {
            guard let superview = root.superview else { break }
            root = superview
        }
        return root
    }

    private func firstCodeTextView(in view: UIView) -> UITextView? {
        let typeName = NSStringFromClass(type(of: view))
        if let textView = view as? UITextView, typeName.contains("CodeView") {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstCodeTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex & 0xFF0000) >> 16) / 255,
            green: CGFloat((hex & 0x00FF00) >> 8) / 255,
            blue: CGFloat(hex & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
#endif
