import Foundation
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
