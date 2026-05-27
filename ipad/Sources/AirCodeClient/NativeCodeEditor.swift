import SwiftUI
import CodeEditorView
import LanguageSupport

public struct NativeCodeEditor: View {
    @Binding var text: String
    let path: String
    let onContextChange: (EditorContextSnapshot) -> Void
    @Environment(\.airCodeTheme) private var theme
    @State private var position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []

    public init(text: Binding<String>, path: String, onContextChange: @escaping (EditorContextSnapshot) -> Void = { _ in }) {
        self._text = text
        self.path = path
        self.onContextChange = onContextChange
    }

    public var body: some View {
        CodeEditor(text: $text, position: $position, messages: $messages, language: language)
            .environment(\.codeEditorTheme, theme.codeEditorTheme)
            .environment(\.codeEditorLayoutConfiguration, CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: false))
            .tint(theme.cursor)
            .background(theme.editor)
            #if os(iOS) || os(visionOS)
            .overlay(CodeEditorCursorTintSynchronizer(cursorHex: theme.cursorHex).allowsHitTesting(false))
            #endif
            .onAppear {
                reportContext(position)
            }
            .onChange(of: position) { _, newPosition in
                reportContext(newPosition)
            }
            .onChange(of: text) { _, _ in
                reportContext(position)
            }
            .onChange(of: path) { _, _ in
                reportContext(position)
            }
    }

    private var language: LanguageConfiguration {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return .swift()
        case "go": return .go()
        case "py": return .python()
        case "sql", "sqlite": return .sqlite()
        default: return .none
        }
    }

    private func reportContext(_ currentPosition: CodeEditor.Position) {
        let selection = currentPosition.selections.first ?? .zero
        let snapshot = EditorContextSnapshot.make(path: path, text: text, selection: selection)
        DispatchQueue.main.async {
            onContextChange(snapshot)
        }
    }
}

#if os(iOS) || os(visionOS)
private struct CodeEditorCursorTintSynchronizer: UIViewRepresentable {
    let cursorHex: UInt32

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        synchronize(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        synchronize(from: uiView)
    }

    private func synchronize(from markerView: UIView) {
        DispatchQueue.main.async {
            let cursorColor = UIColor(hex: cursorHex)
            let searchRoot = nearestSearchRoot(from: markerView)
            if applyCursorTint(in: searchRoot, cursorColor: cursorColor) { return }
            if let window = markerView.window {
                _ = applyCursorTint(in: window, cursorColor: cursorColor)
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
