public struct MarkdownLineStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case heading(level: Int), listItem, plain
    }

    public let kind: Kind
    public let line: Range<String.Index>     // without the line break
    public let marker: Range<String.Index>?  // "## " or "- "

    public static func parse(_ text: String) -> [MarkdownLineStyle] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line in
            let range = line.startIndex..<line.endIndex
            let hashes = line.prefix(while: { $0 == "#" })
            if !hashes.isEmpty, line[hashes.endIndex...].first == " " {
                let markerEnd = line.index(after: hashes.endIndex)
                return MarkdownLineStyle(
                    kind: .heading(level: hashes.count),
                    line: range,
                    marker: line.startIndex..<markerEnd
                )
            }
            if line.hasPrefix("- ") {
                let markerEnd = line.index(line.startIndex, offsetBy: 2)
                return MarkdownLineStyle(kind: .listItem, line: range, marker: line.startIndex..<markerEnd)
            }
            return MarkdownLineStyle(kind: .plain, line: range, marker: nil)
        }
    }
}
