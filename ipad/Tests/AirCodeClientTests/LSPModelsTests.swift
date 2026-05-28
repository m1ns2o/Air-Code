import Foundation
import LanguageSupport
import Testing
@testable import AirCodeClient

@Test func lspPositionMapperUsesUTF16LineAndColumn() {
    let text = "let cloud = \"air\"\nprint(cloud)\n"

    let offset = (text as NSString).range(of: "cloud)").location
    let position = LSPTextPositionMapper.position(in: text, utf16Offset: offset)

    #expect(position.line == 1)
    #expect(position.character == 6)
    #expect(LSPTextPositionMapper.utf16Offset(in: text, position: position) == offset)
}

@Test func lspCompletionApplierReplacesPrefixWhenRangeIsMissing() {
    let result = LSPCompletionApplier.apply(
        item: LSPCompletionItem(label: "console", detail: nil, kind: nil, insertText: nil, range: nil),
        to: "con",
        cursorOffset: 3
    )

    #expect(result.text == "console")
    #expect(result.cursorOffset == "console".utf16.count)
}

@Test func lspCompletionApplierUsesServerRangeWhenPresent() {
    let item = LSPCompletionItem(
        label: "cloud",
        detail: nil,
        kind: nil,
        insertText: "cloudClient",
        range: LSPRange(start: LSPPosition(line: 0, character: 4), end: LSPPosition(line: 0, character: 9))
    )

    let result = LSPCompletionApplier.apply(item: item, to: "let cloud", cursorOffset: 9)

    #expect(result.text == "let cloudClient")
    #expect(result.cursorOffset == "let cloudClient".utf16.count)
}

@Test func webLanguageConfigurationsAreAvailableForEditorHighlighting() {
    #expect(LanguageConfiguration.javascript().name == "JavaScript")
    #expect(LanguageConfiguration.typescript().name == "TypeScript")
    #expect(LanguageConfiguration.vue().name == "Vue")
}

@Test func commonLanguageConfigurationsAreAvailableForEditorHighlighting() {
    #expect(LanguageConfiguration.html().name == "HTML")
    #expect(LanguageConfiguration.css().name == "CSS")
    #expect(LanguageConfiguration.json().name == "JSON")
    #expect(LanguageConfiguration.yaml().name == "YAML")
    #expect(LanguageConfiguration.toml().name == "TOML")
    #expect(LanguageConfiguration.markdown().name == "Markdown")
    #expect(LanguageConfiguration.shell().name == "Shell")
    #expect(LanguageConfiguration.rust().name == "Rust")
    #expect(LanguageConfiguration.java().name == "Java")
    #expect(LanguageConfiguration.kotlin().name == "Kotlin")
    #expect(LanguageConfiguration.cpp().name == "C++")
    #expect(LanguageConfiguration.csharp().name == "C#")
    #expect(LanguageConfiguration.php().name == "PHP")
    #expect(LanguageConfiguration.ruby().name == "Ruby")
    #expect(LanguageConfiguration.dart().name == "Dart")
    #expect(LanguageConfiguration.dockerfile().name == "Dockerfile")
}

@Test func completionTriggerPolicyUsesDotAndIdentifierPrefixes() {
    #expect(LSPCompletionTriggerPolicy.trigger(path: "src/app.ts", text: "client.", cursorUTF16Offset: 7)?.triggerCharacter == ".")
    #expect(LSPCompletionTriggerPolicy.trigger(path: "src/app.ts", text: "con", cursorUTF16Offset: 3)?.prefix == "con")
    #expect(LSPCompletionTriggerPolicy.trigger(path: "src/app.ts", text: "co", cursorUTF16Offset: 2) == nil)
    #expect(LSPCompletionTriggerPolicy.trigger(path: "src/app.ts", text: "c", cursorUTF16Offset: 1) == nil)
    #expect(LSPCompletionTriggerPolicy.trigger(path: "README.md", text: "con", cursorUTF16Offset: 3) == nil)
}

@Test func completionRankerPrioritizesPrefixMatches() {
    let items = [
        LSPCompletionItem(label: "render", detail: nil, kind: nil, insertText: nil, range: nil),
        LSPCompletionItem(label: "connect", detail: nil, kind: nil, insertText: nil, range: nil),
        LSPCompletionItem(label: "console", detail: nil, kind: nil, insertText: nil, range: nil),
        LSPCompletionItem(label: "dispose", detail: nil, kind: nil, insertText: nil, range: nil)
    ]
    let ranked = LSPCompletionRanker.ranked(items, prefix: "con")
    let labels = ranked.map(\.label)
    #expect(Array(labels.prefix(2)) == ["connect", "console"])
    #expect(!labels.contains("render"))
    #expect(!labels.contains("dispose"))
}

@Test func pythonIndentationAddsBlockIndentAfterColon() {
    let text = "def greet():"
    let replacement = EditorIndentationEngine.newlineReplacement(
        text: text,
        path: "main.py",
        selectedRange: NSRange(location: text.utf16.count, length: 0)
    )
    #expect(replacement == "\n    ")
}

@Test func pythonIndentationPreservesExistingIndent() {
    let text = "    if ready:"
    let replacement = EditorIndentationEngine.newlineReplacement(
        text: text,
        path: "main.py",
        selectedRange: NSRange(location: text.utf16.count, length: 0)
    )
    #expect(replacement == "\n        ")
}

@Test func indentationEngineIgnoresNonPythonFiles() {
    let text = "if (ready) {"
    let replacement = EditorIndentationEngine.newlineReplacement(
        text: text,
        path: "main.ts",
        selectedRange: NSRange(location: text.utf16.count, length: 0)
    )
    #expect(replacement == nil)
}
