import Foundation

public enum DiffRowKind: String, Hashable, Sendable {
    case header
    case hunk
    case context
    case added
    case removed
    case folded
}

public struct SideBySideDiffRow: Identifiable, Hashable, Sendable {
    public let id: Int
    public let kind: DiffRowKind
    public let leftLine: Int?
    public let rightLine: Int?
    public let leftText: String
    public let rightText: String

    public var text: String {
        rightText.isEmpty ? leftText : rightText
    }
}

public enum UnifiedDiffParser {
    public static func rows(from diff: String, contextLimit: Int = 16) -> [SideBySideDiffRow] {
        let rawRows = parse(diff)
        return foldContext(rawRows, contextLimit: contextLimit)
    }

    private static func parse(_ diff: String) -> [SideBySideDiffRow] {
        var rows: [SideBySideDiffRow] = []
        var leftLine = 0
        var rightLine = 0

        for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.hasPrefix("@@") {
                let hunk = parseHunk(rawLine)
                leftLine = hunk.left
                rightLine = hunk.right
                rows.append(row(.hunk, leftLine: nil, rightLine: nil, leftText: rawLine, rightText: rawLine, rows.count))
            } else if rawLine.hasPrefix("+"), !rawLine.hasPrefix("+++") {
                rows.append(row(.added, leftLine: nil, rightLine: rightLine, leftText: "", rightText: String(rawLine.dropFirst()), rows.count))
                rightLine += 1
            } else if rawLine.hasPrefix("-"), !rawLine.hasPrefix("---") {
                rows.append(row(.removed, leftLine: leftLine, rightLine: nil, leftText: String(rawLine.dropFirst()), rightText: "", rows.count))
                leftLine += 1
            } else if rawLine.hasPrefix(" ") {
                let text = String(rawLine.dropFirst())
                rows.append(row(.context, leftLine: leftLine, rightLine: rightLine, leftText: text, rightText: text, rows.count))
                leftLine += 1
                rightLine += 1
            } else {
                rows.append(row(.header, leftLine: nil, rightLine: nil, leftText: rawLine, rightText: rawLine, rows.count))
            }
        }
        return rows
    }

    private static func foldContext(_ rows: [SideBySideDiffRow], contextLimit: Int) -> [SideBySideDiffRow] {
        guard contextLimit > 0 else { return rows }
        var result: [SideBySideDiffRow] = []
        var index = 0
        while index < rows.count {
            guard rows[index].kind == .context else {
                result.append(rows[index])
                index += 1
                continue
            }
            let start = index
            while index < rows.count, rows[index].kind == .context {
                index += 1
            }
            let sequence = Array(rows[start..<index])
            if sequence.count <= contextLimit {
                result.append(contentsOf: sequence)
            } else {
                let headCount = max(1, contextLimit / 2)
                let tailCount = max(1, contextLimit - headCount)
                result.append(contentsOf: sequence.prefix(headCount))
                let omitted = sequence.count - headCount - tailCount
                result.append(row(.folded, leftLine: nil, rightLine: nil, leftText: "\(omitted) unchanged lines", rightText: "\(omitted) unchanged lines", result.count))
                result.append(contentsOf: sequence.suffix(tailCount))
            }
        }
        return result.enumerated().map { offset, row in
            SideBySideDiffRow(id: offset, kind: row.kind, leftLine: row.leftLine, rightLine: row.rightLine, leftText: row.leftText, rightText: row.rightText)
        }
    }

    private static func parseHunk(_ line: String) -> (left: Int, right: Int) {
        let parts = line.split(separator: " ")
        let leftPart = parts.first { $0.hasPrefix("-") }.map(String.init) ?? "-1"
        let rightPart = parts.first { $0.hasPrefix("+") }.map(String.init) ?? "+1"
        return (parseStart(leftPart), parseStart(rightPart))
    }

    private static func parseStart(_ value: String) -> Int {
        let trimmed = value.dropFirst()
        let number = trimmed.split(separator: ",", maxSplits: 1).first.map(String.init) ?? "1"
        return Int(number) ?? 1
    }

    private static func row(_ kind: DiffRowKind, leftLine: Int?, rightLine: Int?, leftText: String, rightText: String, _ id: Int) -> SideBySideDiffRow {
        SideBySideDiffRow(id: id, kind: kind, leftLine: leftLine, rightLine: rightLine, leftText: leftText, rightText: rightText)
    }
}
