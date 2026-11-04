import Foundation

/// Reads the signed-in email from the `result` of `account/read`. Only ChatGPT sign-ins carry one;
/// API-key and Bedrock accounts give nil.
public enum CodexAccountMapper {
    public static func email(from result: Data) -> String? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: result),
              let account = root["account"],
              account["type"] == .string("chatgpt"),
              case .string(let email)? = account["email"], !email.isEmpty else { return nil }
        return email
    }
}
