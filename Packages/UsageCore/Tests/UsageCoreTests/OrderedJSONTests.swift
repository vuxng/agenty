import Testing
import UsageCore

@Suite struct OrderedJSONTests {
    @Test func roundTripIsByteIdentical() throws {
        let text = "{\n  \"b\": 1,\n  \"a\": {\n    \"x\": [\n      true,\n      null\n    ]\n  },\n  \"e\": {},\n  \"f\": []\n}\n"
        let document = try OrderedJSON(parsing: text)
        #expect(Array(document.serialized().utf8) == Array(text.utf8))
    }

    @Test(arguments: ["1.0", "1e3", "400000", "-0", "-12.30E+04", "1e999", "9007199254740993"])
    func numbersStayVerbatim(_ text: String) throws {
        let document = try OrderedJSON(parsing: text)
        #expect(document == .number(text))
        #expect(document.serialized() == text + "\n")
    }

    @Test func escapesMatchJSONStringify() throws {
        let text = #""a\"b\n/é😀\u0001""#
        let document = try OrderedJSON(parsing: text)
        #expect(document == .string("a\"b\n/é😀\u{0001}"))
        #expect(document.serialized() == text + "\n")
        let escaped = try OrderedJSON(parsing: #""\\\b\f\r\t\/\u00e9\ud83d\ude00\u001f""#)
        #expect(escaped == .string("\\\u{8}\u{c}\r\t/é😀\u{1f}"))
        #expect(escaped.serialized() == #""\\\b\f\r\t/é😀\u001f""# + "\n")
    }

    @Test func setKeepsOrderAndAppendsNewKeys() throws {
        var document = try OrderedJSON(parsing: #"{"b":1,"a":2,"c":3}"#)
        document.set(.bool(false), at: ["a"])
        document.set(.string("new"), at: ["d"])
        #expect(document.serialized() == "{\n  \"b\": 1,\n  \"a\": false,\n  \"c\": 3,\n  \"d\": \"new\"\n}\n")
        #expect(document.value(at: ["a"]) == .bool(false))
    }

    @Test func setCreatesIntermediateObjects() throws {
        var document = try OrderedJSON(parsing: "{}")
        document.set(.bool(true), at: ["p", "q"])
        #expect(document == .object([.init(key: "p", value: .object([.init(key: "q", value: .bool(true))]))]))
        #expect(document.serialized() == "{\n  \"p\": {\n    \"q\": true\n  }\n}\n")
        #expect(document.value(at: ["p", "q"]) == .bool(true))
    }

    @Test func removePrunesEmptyParents() throws {
        var document = try OrderedJSON(parsing: #"{"m":{"c":{"e":1}},"k":1}"#)
        document.remove(at: ["m", "c", "e"])
        #expect(document.serialized() == "{\n  \"k\": 1\n}\n")
        var siblings = try OrderedJSON(parsing: #"{"m":{"c":{"e":1,"f":2}},"k":1}"#)
        siblings.remove(at: ["m", "c", "e"])
        #expect(siblings.serialized() == "{\n  \"m\": {\n    \"c\": {\n      \"f\": 2\n    }\n  },\n  \"k\": 1\n}\n")
        siblings.remove(at: ["m"])
        siblings.remove(at: ["k"])
        #expect(siblings.serialized() == "{}\n")
    }

    @Test func normalizesForeignFormatting() throws {
        let document = try OrderedJSON(parsing: "{\r\n    \"b\": 1,\r\n    \"a\": [false, {}]\r\n}")
        #expect(document.serialized() == "{\n  \"b\": 1,\n  \"a\": [\n    false,\n    {}\n  ]\n}\n")
        #expect(document.value(at: ["a"]) == .array([.bool(false), .object([])]))
    }

    @Test func invalidReportsLine() {
        do {
            _ = try OrderedJSON(parsing: "{\n  \"a\": ,\n}")
            Issue.record("Expected invalid JSON")
        } catch {
            guard case .invalid(let line, let message) = error else { return }
            #expect(line == 2)
            #expect(!message.isEmpty)
        }
    }

    @Test func duplicateKeysKeepFirstPositionAndLastValue() throws {
        let document = try OrderedJSON(parsing: #"{"b":1,"a":2,"\u0062":{"x":3},"2":4,"1":5}"#)
        #expect(document.serialized() == "{\n  \"b\": {\n    \"x\": 3\n  },\n  \"a\": 2,\n  \"2\": 4,\n  \"1\": 5\n}\n")
    }

    @Test func missingPathsDoNotRemoveExistingValues() throws {
        var document = try OrderedJSON(parsing: #"{"empty":{},"array":[1],"scalar":true}"#)
        let original = document
        for path in [["missing"], ["empty", "missing"], ["array", "0"], ["scalar", "child"]] {
            #expect(document.value(at: path) == nil)
            document.remove(at: path)
            #expect(document == original)
        }
    }

    @Test func setReplacesNonObjectIntermediateValue() throws {
        var document = try OrderedJSON(parsing: #"{"p":false,"keep":[]}"#)
        document.set(.null, at: ["p", "q"])
        #expect(document.serialized() == "{\n  \"p\": {\n    \"q\": null\n  },\n  \"keep\": []\n}\n")
    }

    @Test func emptyPathAddressesRoot() throws {
        var document = try OrderedJSON(parsing: "null")
        #expect(document.value(at: []) == .null)
        document.set(.array([.bool(true)]), at: [])
        #expect(document == .array([.bool(true)]))
        document.remove(at: [])
        #expect(document == .array([.bool(true)]))
    }

    @Test func keysUseStringEscaping() throws {
        let document = OrderedJSON.object([.init(key: "a\"\\\n\u{0}", value: .null)])
        #expect(document.serialized() == "{\n  \"a\\\"\\\\\\n\\u0000\": null\n}\n")
        #expect(try OrderedJSON(parsing: document.serialized()) == document)
    }

    @Test func distinctUnicodeKeySpellingsStaySeparate() throws {
        var document = try OrderedJSON(parsing: #"{"é":1,"e\u0301":2}"#)
        #expect(document.value(at: ["é"]) == .number("1"))
        #expect(document.value(at: ["e\u{301}"]) == .number("2"))
        document.set(.bool(true), at: ["e\u{301}"])
        #expect(Array(document.serialized().utf8) == Array("{\n  \"é\": 1,\n  \"e\u{301}\": true\n}\n".utf8))
        document.remove(at: ["é"])
        #expect(Array(document.serialized().utf8) == Array("{\n  \"e\u{301}\": true\n}\n".utf8))
    }

    @Test(arguments: [
        "", " ", "nul", "True", "false true", "{}x", "[1,]", "{\"a\":1,}",
        "{a:1}", "{\"a\" 1}", "[1 2]", "[", "{", "\"unterminated", "\"raw\nline\"",
        "\"\u{0}\"", #""\x""#, #""\uZZZZ""#, #""\u123""#,
        #""\ud800""#, #""\udc00""#, #""\ud800\u0041""#,
        "+1", "01", "-01", "-", ".5", "1.", "1e", "1e+", "NaN", "Infinity", "\u{a0}null",
    ])
    func rejectsInvalidJSON(_ text: String) {
        #expect(throws: OrderedJSONError.self) { try OrderedJSON(parsing: text) }
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func reportsLinesAcrossWhitespace(_ newline: String) {
        do {
            _ = try OrderedJSON(parsing: "{" + newline + "\"a\": [" + newline + ",]")
            Issue.record("Expected invalid JSON")
        } catch {
            guard case .invalid(let line, _) = error else { return }
            #expect(line == 3)
        }
    }
}
