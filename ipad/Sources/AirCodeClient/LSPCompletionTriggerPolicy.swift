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
    private static let minimumIdentifierPrefixLength = 3

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
        guard prefix.count >= minimumIdentifierPrefixLength else { return nil }
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

public enum LSPCompletionRanker {
    public static func ranked(_ items: [LSPCompletionItem], prefix: String?, limit: Int = 40) -> [LSPCompletionItem] {
        let normalizedPrefix = (prefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrefix.isEmpty else {
            return Array(items.prefix(limit))
        }

        let scored = items.map { item in
            (item: item, score: score(item, prefix: normalizedPrefix))
        }
        let filtered = scored.filter { $0.score < 100 }
        let candidates = filtered.isEmpty ? scored : filtered
        return Array(candidates
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.item.label.count != rhs.item.label.count { return lhs.item.label.count < rhs.item.label.count }
                return lhs.item.label.localizedCaseInsensitiveCompare(rhs.item.label) == .orderedAscending
            }
            .map(\.item)
            .prefix(limit))
    }

    private static func score(_ item: LSPCompletionItem, prefix: String) -> Int {
        let label = item.label
        let insertText = item.insertText ?? item.label
        let lowerPrefix = prefix.lowercased()
        let lowerLabel = label.lowercased()
        let lowerInsertText = insertText.lowercased()

        if label == prefix { return 0 }
        if lowerLabel == lowerPrefix { return 1 }
        if label.hasPrefix(prefix) { return 2 }
        if lowerLabel.hasPrefix(lowerPrefix) { return 3 }
        if lowerInsertText.hasPrefix(lowerPrefix) { return 4 }
        if lowerLabel.contains(lowerPrefix) { return 8 }
        if lowerInsertText.contains(lowerPrefix) { return 9 }
        return 100
    }
}
