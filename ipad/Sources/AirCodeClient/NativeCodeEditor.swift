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

public enum CodeEditorCompletionCommand {
    case accept
}

public struct NativeCodeEditor: View {
    @Binding var text: String
    let path: String
    let selectionRequest: EditorSelectionRequest?
    let diagnostics: [LSPDiagnostic]
    let onContextChange: (EditorContextSnapshot) -> Void
    let onCaretRectChange: (CGRect?) -> Void
    let onCompletionCommand: (CodeEditorCompletionCommand) -> Bool
    @Environment(\.airCodeTheme) private var theme
    @State private var position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []
    @State private var contextReportTask: Task<Void, Never>?

    public init(
        text: Binding<String>,
        path: String,
        selectionRequest: EditorSelectionRequest? = nil,
        diagnostics: [LSPDiagnostic] = [],
        onContextChange: @escaping (EditorContextSnapshot) -> Void = { _ in },
        onCaretRectChange: @escaping (CGRect?) -> Void = { _ in },
        onCompletionCommand: @escaping (CodeEditorCompletionCommand) -> Bool = { _ in false }
    ) {
        self._text = text
        self.path = path
        self.selectionRequest = selectionRequest
        self.diagnostics = diagnostics
        self.onContextChange = onContextChange
        self.onCaretRectChange = onCaretRectChange
        self.onCompletionCommand = onCompletionCommand
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
                    CodeEditorCaretRectReporter(onChange: onCaretRectChange)
                    CodeEditorInputInterceptor(path: path, onCompletionCommand: onCompletionCommand)
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
                onCaretRectChange(nil)
            }
            .onChange(of: position) { _, newPosition in
                scheduleContextReport(newPosition, delayNanoseconds: 60_000_000)
            }
            .onChange(of: text) { _, _ in
                scheduleContextReport(position, delayNanoseconds: 90_000_000)
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
        let filename = (path as NSString).lastPathComponent.lowercased()
        if filename == "dockerfile" || filename.hasPrefix("dockerfile.") {
            return .dockerfile()
        }
        if filename == "makefile" || filename.hasPrefix("makefile.") {
            return .shell()
        }
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return .swift()
        case "go": return .go()
        case "py": return .python()
        case "js", "jsx", "mjs", "cjs": return .javascript()
        case "ts", "tsx", "mts", "cts": return .typescript()
        case "vue": return .vue()
        case "html", "htm", "xml", "svg": return .html()
        case "css", "scss", "sass", "less": return .css()
        case "json", "jsonc": return .json()
        case "yml", "yaml": return .yaml()
        case "toml": return .toml()
        case "md", "markdown", "mdx": return .markdown()
        case "sh", "bash", "zsh", "fish": return .shell()
        case "rs": return .rust()
        case "java": return .java()
        case "kt", "kts": return .kotlin()
        case "c": return .c()
        case "h", "cc", "cpp", "cxx", "hh", "hpp", "hxx": return .cpp()
        case "cs": return .csharp()
        case "php": return .php()
        case "rb": return .ruby()
        case "dart": return .dart()
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

private struct CodeEditorInputInterceptor: UIViewRepresentable {
    let path: String
    let onCompletionCommand: (CodeEditorCompletionCommand) -> Bool

    final class Coordinator {
        weak var textView: UITextView?
        var proxy: DelegateProxy?
        var isScheduled = false
    }

    final class DelegateProxy: NSObject, UITextViewDelegate {
        weak var original: (NSObjectProtocol & UITextViewDelegate)?
        var path: String = ""
        var onCompletionCommand: ((CodeEditorCompletionCommand) -> Bool)?
        private var isApplyingProgrammaticReplacement = false

        init(original: (NSObjectProtocol & UITextViewDelegate)?) {
            self.original = original
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if !isApplyingProgrammaticReplacement {
                if replacement == "\t", onCompletionCommand?(.accept) == true {
                    return false
                }

                if replacement == "\n" {
                    if onCompletionCommand?(.accept) == true {
                        return false
                    }
                    if let smartReplacement = EditorIndentationEngine.newlineReplacement(text: textView.text ?? "", path: path, selectedRange: range) {
                        apply(smartReplacement, in: textView, range: range)
                        return false
                    }
                }
            }

            return original?.textView?(textView, shouldChangeTextIn: range, replacementText: replacement) ?? true
        }

        func textViewDidChange(_ textView: UITextView) {
            original?.textViewDidChange?(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            original?.textViewDidChangeSelection?(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            original?.textViewDidBeginEditing?(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            original?.textViewDidEndEditing?(textView)
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true {
                return original
            }
            return super.forwardingTarget(for: selector)
        }

        private func apply(_ replacement: String, in textView: UITextView, range: NSRange) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            isApplyingProgrammaticReplacement = true
            textView.replace(textRange, withText: replacement)
            isApplyingProgrammaticReplacement = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        install(from: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        install(from: uiView, coordinator: context.coordinator)
    }

    private func install(from markerView: UIView, coordinator: Coordinator) {
        guard !coordinator.isScheduled else {
            coordinator.proxy?.path = path
            coordinator.proxy?.onCompletionCommand = onCompletionCommand
            return
        }
        coordinator.isScheduled = true
        DispatchQueue.main.async {
            coordinator.isScheduled = false
            guard let textView = findCodeTextView(from: markerView) else { return }

            let activeDelegate = textView.delegate
            if coordinator.textView !== textView || activeDelegate !== coordinator.proxy {
                let proxy = DelegateProxy(original: activeDelegate as? (NSObjectProtocol & UITextViewDelegate))
                textView.delegate = proxy
                coordinator.proxy = proxy
                coordinator.textView = textView
            }
            coordinator.proxy?.path = path
            coordinator.proxy?.onCompletionCommand = onCompletionCommand
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

private struct CodeEditorCaretRectReporter: UIViewRepresentable {
    let onChange: (CGRect?) -> Void

    final class Coordinator {
        var lastRect: CGRect?
        var isScheduled = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        report(from: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        report(from: uiView, coordinator: context.coordinator)
    }

    private func report(from markerView: UIView, coordinator: Coordinator) {
        guard !coordinator.isScheduled else { return }
        coordinator.isScheduled = true
        DispatchQueue.main.async {
            coordinator.isScheduled = false
            guard let textView = findCodeTextView(from: markerView),
                  let selectedRange = textView.selectedTextRange else {
                publish(nil, coordinator: coordinator)
                return
            }
            let caretRect = textView.caretRect(for: selectedRange.end)
            guard caretRect.isFiniteAndVisible else {
                publish(nil, coordinator: coordinator)
                return
            }
            let converted = markerView.convert(caretRect, from: textView)
            guard converted.isFiniteAndVisible else {
                publish(nil, coordinator: coordinator)
                return
            }
            publish(converted.integral, coordinator: coordinator)
        }
    }

    private func publish(_ rect: CGRect?, coordinator: Coordinator) {
        if coordinator.lastRect == rect { return }
        coordinator.lastRect = rect
        onChange(rect)
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

private extension CGRect {
    var isFiniteAndVisible: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite && !isNull && !isInfinite
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
