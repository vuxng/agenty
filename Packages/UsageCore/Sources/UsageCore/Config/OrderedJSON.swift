public enum OrderedJSONError: Error, Sendable, Equatable {
    case invalid(line: Int, message: String)
}

public indirect enum OrderedJSON: Sendable, Equatable {
    public struct Member: Sendable, Equatable {
        public var key: String
        public var value: OrderedJSON

        public init(key: String, value: OrderedJSON) {
            self.key = key
            self.value = value
        }
    }

    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([OrderedJSON])
    case object([Member])

    public init(parsing text: String) throws(OrderedJSONError) {
        var parser = Parser(text)
        self = try parser.parse()
    }

    public func serialized() -> String {
        formatted(depth: 0) + "\n"
    }

    public func value(at path: [String]) -> OrderedJSON? {
        var value = self
        for key in path {
            guard case .object(let members) = value,
                  let member = members.first(where: { $0.key.utf8.elementsEqual(key.utf8) }) else { return nil }
            value = member.value
        }
        return value
    }

    public mutating func set(_ value: OrderedJSON, at path: [String]) {
        guard let key = path.first else {
            self = value
            return
        }
        var members: [Member]
        if case .object(let existing) = self { members = existing } else { members = [] }
        if let index = members.firstIndex(where: { $0.key.utf8.elementsEqual(key.utf8) }) {
            members[index].value.set(value, at: Array(path.dropFirst()))
        } else {
            var child = OrderedJSON.object([])
            child.set(value, at: Array(path.dropFirst()))
            members.append(Member(key: key, value: child))
        }
        self = .object(members)
    }

    public mutating func remove(at path: [String]) {
        _ = removeValue(at: path[...])
    }

    private mutating func removeValue(at path: ArraySlice<String>) -> Bool {
        guard let key = path.first, case .object(var members) = self,
              let index = members.firstIndex(where: { $0.key.utf8.elementsEqual(key.utf8) }) else { return false }
        if path.count == 1 {
            members.remove(at: index)
        } else {
            guard members[index].value.removeValue(at: path.dropFirst()) else { return false }
            if case .object(let children) = members[index].value, children.isEmpty {
                members.remove(at: index)
            }
        }
        self = .object(members)
        return true
    }

    private func formatted(depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let childIndent = indent + "  "
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return value
        case .string(let value): return Self.quoted(value)
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            let lines = values.map { childIndent + $0.formatted(depth: depth + 1) }
            return "[\n" + lines.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let members):
            guard !members.isEmpty else { return "{}" }
            let lines = members.map {
                childIndent + Self.quoted($0.key) + ": " + $0.value.formatted(depth: depth + 1)
            }
            return "{\n" + lines.joined(separator: ",\n") + "\n" + indent + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x08: result += "\\b"
            case 0x0C: result += "\\f"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0...0x1F:
                let hex = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}

private struct Parser {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var line = 1

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    mutating func parse() throws(OrderedJSONError) -> OrderedJSON {
        let value = try parseValue()
        skipWhitespace()
        guard current == nil else { throw invalid("Unexpected content after JSON value") }
        return value
    }

    private var current: Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    private func invalid(_ message: String) -> OrderedJSONError {
        .invalid(line: line, message: message)
    }

    private mutating func advance() {
        if current == "\n" || (current == "\r" && (index + 1 == scalars.count || scalars[index + 1] != "\n")) {
            line += 1
        }
        index += 1
    }

    private mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
        guard current == scalar else { return false }
        advance()
        return true
    }

    private mutating func skipWhitespace() {
        while let scalar = current, scalar == " " || scalar == "\t" || scalar == "\r" || scalar == "\n" {
            advance()
        }
    }

    private mutating func parseValue() throws(OrderedJSONError) -> OrderedJSON {
        skipWhitespace()
        switch current {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return .string(try parseString())
        case "t":
            try parseLiteral("true")
            return .bool(true)
        case "f":
            try parseLiteral("false")
            return .bool(false)
        case "n":
            try parseLiteral("null")
            return .null
        case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return .number(try parseNumber())
        default: throw invalid("Expected a JSON value")
        }
    }

    private mutating func parseObject() throws(OrderedJSONError) -> OrderedJSON {
        advance()
        skipWhitespace()
        var members: [OrderedJSON.Member] = []
        if consume("}") { return .object(members) }
        while true {
            guard current == "\"" else { throw invalid("Expected an object key") }
            let key = try parseString()
            skipWhitespace()
            guard consume(":") else { throw invalid("Expected ':' after object key") }
            let value = try parseValue()
            if let index = members.firstIndex(where: { $0.key.utf8.elementsEqual(key.utf8) }) {
                members[index].value = value
            } else {
                members.append(.init(key: key, value: value))
            }
            skipWhitespace()
            if consume("}") { return .object(members) }
            guard consume(",") else { throw invalid("Expected ',' or '}'") }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws(OrderedJSONError) -> OrderedJSON {
        advance()
        skipWhitespace()
        var values: [OrderedJSON] = []
        if consume("]") { return .array(values) }
        while true {
            values.append(try parseValue())
            skipWhitespace()
            if consume("]") { return .array(values) }
            guard consume(",") else { throw invalid("Expected ',' or ']'") }
        }
    }

    private mutating func parseLiteral(_ literal: String) throws(OrderedJSONError) {
        for scalar in literal.unicodeScalars {
            guard consume(scalar) else { throw invalid("Invalid JSON literal") }
        }
    }

    private mutating func parseNumber() throws(OrderedJSONError) -> String {
        let start = index
        _ = consume("-")
        if !consume("0") {
            guard let scalar = current, scalar >= "1", scalar <= "9" else { throw invalid("Expected a digit") }
            consumeDigits()
        }
        if consume(".") {
            let fractionStart = index
            consumeDigits()
            guard index > fractionStart else { throw invalid("Expected a digit after decimal point") }
        }
        if consume("e") || consume("E") {
            if !consume("+") { _ = consume("-") }
            let exponentStart = index
            consumeDigits()
            guard index > exponentStart else { throw invalid("Expected an exponent digit") }
        }
        return String(String.UnicodeScalarView(scalars[start..<index]))
    }

    private mutating func consumeDigits() {
        while let scalar = current, scalar >= "0", scalar <= "9" { advance() }
    }

    private mutating func parseString() throws(OrderedJSONError) -> String {
        advance()
        var result = ""
        while let scalar = current {
            if consume("\"") { return result }
            guard scalar.value >= 0x20 else { throw invalid("Unescaped control character in string") }
            advance()
            if scalar != "\\" {
                result.unicodeScalars.append(scalar)
                continue
            }
            guard let escape = current else { throw invalid("Unterminated string escape") }
            advance()
            switch escape {
            case "\"", "\\", "/": result.unicodeScalars.append(escape)
            case "b": result += "\u{8}"
            case "f": result += "\u{c}"
            case "n": result += "\n"
            case "r": result += "\r"
            case "t": result += "\t"
            case "u": result.unicodeScalars.append(try parseUnicodeEscape())
            default: throw invalid("Invalid string escape")
            }
        }
        throw invalid("Unterminated string")
    }

    private mutating func parseUnicodeEscape() throws(OrderedJSONError) -> Unicode.Scalar {
        let first = try parseHexQuad()
        var value = first
        if (0xD800...0xDBFF).contains(first) {
            guard consume("\\"), consume("u") else { throw invalid("Expected a low surrogate escape") }
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw invalid("Invalid low surrogate") }
            value = 0x10000 + (first - 0xD800) * 0x400 + second - 0xDC00
        }
        guard let scalar = Unicode.Scalar(value) else { throw invalid("Invalid Unicode scalar") }
        return scalar
    }

    private mutating func parseHexQuad() throws(OrderedJSONError) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let scalar = current else { throw invalid("Incomplete Unicode escape") }
            let digit: UInt32
            switch scalar.value {
            case 0x30...0x39: digit = scalar.value - 0x30
            case 0x41...0x46: digit = scalar.value - 0x41 + 10
            case 0x61...0x66: digit = scalar.value - 0x61 + 10
            default: throw invalid("Invalid Unicode escape")
            }
            value = value * 16 + digit
            advance()
        }
        return value
    }
}
