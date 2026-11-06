import Testing
@testable import UsageCore

@Suite struct MarkdownLineStyleTests {
    @Test func headingLevels() throws {
        for (text, level, expectedMarker) in [("# a", 1, "# "), ("## a", 2, "## "), ("### a", 3, "### ")] {
            let styles = MarkdownLineStyle.parse(text)
            #expect(styles.count == 1)
            let style = try #require(styles.first)
            #expect(style.kind == .heading(level: level))
            #expect(text[style.line] == text)
            let marker = try #require(style.marker)
            #expect(text[marker] == expectedMarker)
        }
    }

    @Test func hashWithoutSpaceIsPlain() throws {
        let text = "#tag"
        let styles = MarkdownLineStyle.parse(text)
        #expect(styles.count == 1)
        let style = try #require(styles.first)
        #expect(style.kind == .plain)
        #expect(style.marker == nil)
        #expect(text[style.line] == "#tag")
    }

    @Test func listItem() throws {
        let text = "- a"
        let styles = MarkdownLineStyle.parse(text)
        #expect(styles.count == 1)
        let style = try #require(styles.first)
        #expect(style.kind == .listItem)
        #expect(text[style.line] == "- a")
        let marker = try #require(style.marker)
        #expect(text[marker] == "- ")

        let plainText = "-a"
        let plainStyles = MarkdownLineStyle.parse(plainText)
        #expect(plainStyles.count == 1)
        let plain = try #require(plainStyles.first)
        #expect(plain.kind == .plain)
        #expect(plain.marker == nil)
        #expect(plainText[plain.line] == "-a")
    }

    @Test func blankAndPlain() throws {
        for text in ["", "plain text"] {
            let styles = MarkdownLineStyle.parse(text)
            #expect(styles.count == 1)
            let style = try #require(styles.first)
            #expect(style.kind == .plain)
            #expect(style.marker == nil)
            #expect(text[style.line] == text)
        }
    }

    @Test func crlfLinesExcludeBreak() throws {
        let text = "# a\r\nb"
        let styles = MarkdownLineStyle.parse(text)
        try #require(styles.count == 2)
        #expect(text[styles[0].line] == "# a")
        #expect(styles[0].kind == .heading(level: 1))
        let marker = try #require(styles[0].marker)
        #expect(text[marker] == "# ")
        #expect(text[styles[1].line] == "b")
        #expect(styles[1].kind == .plain)
        #expect(styles[1].marker == nil)
    }

    @Test func vietnameseIndices() throws {
        let text = "# Tiếng Việt"
        let styles = MarkdownLineStyle.parse(text)
        #expect(styles.count == 1)
        let style = try #require(styles.first)
        #expect(style.kind == .heading(level: 1))
        #expect(text[style.line] == "# Tiếng Việt")
        let marker = try #require(style.marker)
        #expect(text[marker] == "# ")
    }

    @Test func lfLinesPreserveBlankLinesAndOriginalIndices() throws {
        let text = "Tiếng Việt\n\n- a\n"
        let styles = MarkdownLineStyle.parse(text)
        try #require(styles.count == 4)
        #expect(styles.map { String(text[$0.line]) } == ["Tiếng Việt", "", "- a", ""])
        #expect(styles.map(\.kind) == [.plain, .plain, .listItem, .plain])
        #expect(styles[0].marker == nil)
        #expect(styles[1].marker == nil)
        #expect(styles[3].marker == nil)
        let marker = try #require(styles[2].marker)
        #expect(text[marker] == "- ")
        #expect(marker.lowerBound == styles[2].line.lowerBound)
        #expect(styles[3].line == text.endIndex..<text.endIndex)
    }
}
