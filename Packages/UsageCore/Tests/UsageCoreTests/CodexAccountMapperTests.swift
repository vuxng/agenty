import Foundation
import Testing
@testable import UsageCore

@Suite struct CodexAccountMapperTests {
    @Test func chatgptAccountGivesEmail() {
        let json = #"{"account":{"type":"chatgpt","email":"user@example.com","planType":"pro"},"requiresOpenaiAuth":true}"#
        #expect(CodexAccountMapper.email(from: Data(json.utf8)) == "user@example.com")
    }

    @Test(arguments: [
        #"{"account":{"type":"apiKey"},"requiresOpenaiAuth":true}"#,
        #"{"account":{"type":"amazonBedrock","usesCodexManagedCredentials":true},"requiresOpenaiAuth":false}"#,
        #"{"account":{"type":"chatgpt","email":null,"planType":"pro"},"requiresOpenaiAuth":true}"#,
        #"{"account":{"type":"chatgpt","email":"","planType":"pro"},"requiresOpenaiAuth":true}"#,
        #"{"account":null,"requiresOpenaiAuth":true}"#,
        #"null"#,
        #"not json"#,
    ])
    func noEmailIsNil(json: String) {
        #expect(CodexAccountMapper.email(from: Data(json.utf8)) == nil)
    }
}
