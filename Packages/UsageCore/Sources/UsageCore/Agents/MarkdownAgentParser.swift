import Foundation
import Yams

public enum MarkdownAgentParser {
    public static func parse(_ text: String, url: URL) -> AgentDefinition? {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.first == "\u{FEFF}" { normalized.removeFirst() }
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first.map { trimEnd($0) } == "---",
              let end = lines.indices.dropFirst().first(where: {
                  trimEnd(lines[$0]) == "---"
              }) else { return nil }
        let header = Array(lines[1..<end])
        var body = Array(lines.dropFirst(end + 1))
        while body.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeFirst() }
        let prompt = trimEnd(body.joined(separator: "\n"))
        var entries: [AgentField] = []
        var scanned = false
        do {
            guard let node = try Yams.compose(yaml: header.joined(separator: "\n") + "\n"),
                  case .mapping(let mapping) = node else { return nil }
            for (key, value) in mapping {
                guard case .scalar(let scalarKey) = key else { continue }
                let fieldValue: AgentFieldValue
                switch value {
                case .scalar(let scalar):
                    let string = scalar.string.contains("\n") ? trimEnd(scalar.string) : scalar.string
                    fieldValue = scalar.string.contains("\n") ? .block(string) : .text(string)
                case .sequence(let sequence):
                    let strings = sequence.compactMap { node -> String? in
                        guard case .scalar(let scalar) = node, !scalar.string.contains("\n") else { return nil }
                        return scalar.string
                    }
                    fieldValue = strings.count == sequence.count ? .text(strings.joined(separator: ", ")) : .block(rawValue(header, at: (key.mark?.line ?? 1) - 1))
                case .mapping, .alias:
                    fieldValue = .block(rawValue(header, at: (key.mark?.line ?? 1) - 1))
                }
                entries.append(AgentField(key: scalarKey.string, value: fieldValue))
            }
        } catch {
            scanned = true
            let pattern = #"^([A-Za-z_][A-Za-z0-9_.-]*):(?:\s+(.*))?$"#
            let regex = try! NSRegularExpression(pattern: pattern)
            for (index, line) in header.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, range: range),
                      let keyRange = Range(match.range(at: 1), in: line) else { continue }
                let inline = Range(match.range(at: 2), in: line).map { String(line[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
                let value: AgentFieldValue = inline.isEmpty ? .block(rawValue(header, at: index)) : .text(unquote(inline))
                entries.append(AgentField(key: String(line[keyRange]), value: value))
            }
        }
        func string(_ key: String) -> String? {
            guard let value = entries.first(where: { $0.key == key })?.value else { return nil }
            switch value { case .text(let text), .block(let text): return text }
        }
        guard let name = string("name")?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let model = string("model")
        return AgentDefinition(url: url, name: name, description: string("description"),
                               model: model == "inherit" ? nil : model,
                               fields: entries.filter { !["name", "description", "model", "prompt"].contains($0.key) },
                               prompt: prompt.isEmpty ? nil : prompt, isLineScanned: scanned)
    }

    private static func rawValue(_ lines: [String], at index: Int) -> String {
        guard lines.indices.contains(index), let colon = lines[index].firstIndex(of: ":") else { return "" }
        let inline = String(lines[index][lines[index].index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        var nested: [String] = []
        for line in lines.dropFirst(index + 1) {
            if !line.isEmpty && line.first != " " && line.first != "\t" && line.first != "#" { break }
            nested.append(line)
        }
        while nested.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { nested.removeLast() }
        let indent = nested.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        let dedented = nested.map { String($0.dropFirst(min(indent, $0.count))) }
        let isBlockIndicator = inline.range(of: #"^[|>][-+0-9]*$"#, options: .regularExpression) != nil
        return ((inline.isEmpty || isBlockIndicator ? [] : [inline]) + dedented).joined(separator: "\n")
    }

    private static func unquote(_ value: String) -> String {
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func trimEnd(_ value: String) -> String {
        String(value.reversed().drop(while: { $0.isWhitespace }).reversed())
    }
}
