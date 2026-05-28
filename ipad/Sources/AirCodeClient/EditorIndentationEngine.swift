import Foundation

public enum EditorIndentationEngine {
    public static func newlineReplacement(text: String, path: String, selectedRange: NSRange, indentUnit: String = "    ") -> String? {
        guard isPythonPath(path) else { return nil }
        let boundedLocation = min(max(0, selectedRange.location), text.utf16.count)
        guard let cursorRange = Range(NSRange(location: boundedLocation, length: 0), in: text) else {
            return "\n"
        }
        let cursor = cursorRange.lowerBound
        let lineStart = text[..<cursor].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let line = String(text[lineStart..<cursor])
        let leadingWhitespace = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if trimmedLine.hasSuffix(":") {
            return "\n" + leadingWhitespace + indentUnit
        }
        return "\n" + leadingWhitespace
    }

    private static func isPythonPath(_ path: String) -> Bool {
        (path as NSString).pathExtension.lowercased() == "py"
    }
}
