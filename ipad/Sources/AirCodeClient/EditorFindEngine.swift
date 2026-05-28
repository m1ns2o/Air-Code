import Foundation

public enum EditorFindEngine {
    public static func matches(in text: String, query: String, caseSensitive: Bool = false) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var matches: [NSRange] = []
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: query, options: options, range: searchRange, locale: nil) {
            guard range.lowerBound < range.upperBound else { break }
            matches.append(NSRange(range, in: text))
            guard range.upperBound < text.endIndex else { break }
            searchRange = range.upperBound..<text.endIndex
        }

        return matches
    }

    public static func nextIndex(currentIndex: Int?, matchCount: Int, direction: SearchDirection) -> Int? {
        guard matchCount > 0 else { return nil }
        guard let currentIndex, currentIndex >= 0, currentIndex < matchCount else {
            return direction == .forward ? 0 : matchCount - 1
        }
        switch direction {
        case .forward:
            return (currentIndex + 1) % matchCount
        case .backward:
            return (currentIndex - 1 + matchCount) % matchCount
        }
    }

    public static func replace(in text: String, range: NSRange, with replacement: String) -> String? {
        guard let stringRange = Range(range, in: text) else { return nil }
        var updated = text
        updated.replaceSubrange(stringRange, with: replacement)
        return updated
    }

    public static func replaceAll(in text: String, query: String, replacement: String, caseSensitive: Bool = false) -> (text: String, count: Int) {
        let matches = matches(in: text, query: query, caseSensitive: caseSensitive)
        guard !matches.isEmpty else { return (text, 0) }
        var updated = text
        for match in matches.reversed() {
            guard let range = Range(match, in: updated) else { continue }
            updated.replaceSubrange(range, with: replacement)
        }
        return (updated, matches.count)
    }
}

public enum SearchDirection {
    case forward
    case backward
}
