import Testing
@testable import AirCodeClient

@Test func unifiedDiffParserBuildsSideBySideRows() {
    let diff = """
    diff --git a/main.go b/main.go
    @@ -10,3 +10,4 @@
     keep
    -old
    +new
    +added
    """

    let rows = UnifiedDiffParser.rows(from: diff, contextLimit: 16)

    #expect(rows.contains { $0.kind == .hunk })
    #expect(rows.contains { $0.kind == .context && $0.leftLine == 10 && $0.rightLine == 10 && $0.leftText == "keep" })
    #expect(rows.contains { $0.kind == .removed && $0.leftLine == 11 && $0.rightLine == nil && $0.leftText == "old" })
    #expect(rows.contains { $0.kind == .added && $0.leftLine == nil && $0.rightLine == 11 && $0.rightText == "new" })
    #expect(rows.contains { $0.kind == .added && $0.rightLine == 12 && $0.rightText == "added" })
}

@Test func unifiedDiffParserFoldsLargeContextBlocks() {
    let context = (1...20).map { " line\($0)" }.joined(separator: "\n")
    let diff = """
    @@ -1,20 +1,20 @@
    \(context)
    """

    let rows = UnifiedDiffParser.rows(from: diff, contextLimit: 8)

    #expect(rows.contains { $0.kind == .folded && $0.text == "12 unchanged lines" })
    #expect(rows.count == 10)
}
