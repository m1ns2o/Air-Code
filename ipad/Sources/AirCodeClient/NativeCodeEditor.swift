import SwiftUI
import CodeEditorView
import LanguageSupport

public struct NativeCodeEditor: View {
    @Binding var text: String
    let path: String
    @State private var position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = []

    public init(text: Binding<String>, path: String) {
        self._text = text
        self.path = path
    }

    public var body: some View {
        CodeEditor(text: $text, position: $position, messages: $messages, language: language)
            .font(.system(.body, design: .monospaced))
    }

    private var language: LanguageConfiguration {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return .swift()
        case "py": return .python()
        case "sql", "sqlite": return .sqlite()
        default: return .none
        }
    }
}
