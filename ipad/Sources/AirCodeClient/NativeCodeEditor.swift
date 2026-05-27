import SwiftUI
import CodeEditorView
import LanguageSupport

public struct NativeCodeEditor: View {
    @Binding var text: String
    let path: String
    @Environment(\.airCodeTheme) private var theme
    @State private var position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []

    public init(text: Binding<String>, path: String) {
        self._text = text
        self.path = path
    }

    public var body: some View {
        CodeEditor(text: $text, position: $position, messages: $messages, language: language)
            .environment(\.codeEditorTheme, theme.codeEditorTheme)
            .environment(\.codeEditorLayoutConfiguration, CodeEditor.LayoutConfiguration(showMinimap: false, wrapText: false))
            .tint(theme.cursor)
            .background(theme.editor)
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
}
