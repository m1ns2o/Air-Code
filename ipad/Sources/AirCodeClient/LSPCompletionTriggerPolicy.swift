import Foundation

public struct LSPAutoCompletionTrigger: Equatable, Sendable {
    public let triggerCharacter: String?
    public let prefix: String
    public let cursorUTF16Offset: Int

    public init(triggerCharacter: String?, prefix: String, cursorUTF16Offset: Int) {
        self.triggerCharacter = triggerCharacter
        self.prefix = prefix
        self.cursorUTF16Offset = cursorUTF16Offset
    }
}

public enum LSPCompletionTriggerPolicy {
    private static let identifierCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))

    public static func isAutoCompletionPath(_ path: String) -> Bool {
        switch (path as NSString).pathExtension.lowercased() {
        case "ts", "tsx", "js", "jsx", "mjs", "cjs", "mts", "cts", "py", "vue":
            return true
        default:
            return false
        }
    }

    public static func trigger(path: String, text: String, cursorUTF16Offset: Int) -> LSPAutoCompletionTrigger? {
        guard isAutoCompletionPath(path) else { return nil }
        let boundedOffset = min(max(0, cursorUTF16Offset), text.utf16.count)
        guard boundedOffset > 0,
              let cursorRange = Range(NSRange(location: boundedOffset, length: 0), in: text) else {
            return nil
        }
        let cursorIndex = cursorRange.lowerBound
        guard cursorIndex > text.startIndex else { return nil }
        let previousIndex = text.index(before: cursorIndex)
        let previous = text[previousIndex]

        if previous == "." {
            return LSPAutoCompletionTrigger(triggerCharacter: ".", prefix: "", cursorUTF16Offset: boundedOffset)
        }

        guard isIdentifierCharacter(previous) else { return nil }
        let prefix = identifierPrefix(before: cursorIndex, in: text)
        guard prefix.count >= 2 else { return nil }
        return LSPAutoCompletionTrigger(triggerCharacter: nil, prefix: prefix, cursorUTF16Offset: boundedOffset)
    }

    private static func identifierPrefix(before cursorIndex: String.Index, in text: String) -> String {
        var start = cursorIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard isIdentifierCharacter(text[previous]) else { break }
            start = previous
        }
        return String(text[start..<cursorIndex])
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { identifierCharacterSet.contains($0) }
    }
}
