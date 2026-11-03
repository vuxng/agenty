import Foundation

/// Maps the `result` of `account/rateLimits/read` to a `UsageSnapshot`.
public enum CodexRateLimitsMapper {
    public static func snapshot(from result: Data, fetchedAt: Date) throws(UsageError) -> UsageSnapshot {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: result),
              case .object = root else {
            throw .unexpectedFormat("codex result is not a JSON object")
        }
        guard let limits = root["rateLimits"] else {
            throw .unexpectedFormat("codex result has no rateLimits")
        }
        if limits == .null { throw .notLoggedIn }
        guard case .object = limits else {
            throw .unexpectedFormat("codex rateLimits is not an object")
        }

        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let raw = limits[key], raw != .null else { continue }
            windows.append(try window(from: raw))
        }

        var plan: String?
        if case .string(let p)? = limits["planType"] { plan = p }

        return UsageSnapshot(provider: .codex, plan: plan, windows: windows,
                             credits: credits(from: limits["credits"]), fetchedAt: fetchedAt)
    }

    private static func window(from raw: JSONValue) throws(UsageError) -> UsageWindow {
        guard case .object = raw, case .number(let used)? = raw["usedPercent"] else {
            throw .unexpectedFormat("codex window has no usedPercent")
        }
        let kind: WindowKind
        switch raw["windowDurationMins"]?.intValue {
        case 300?: kind = .session5h
        case 10080?: kind = .weekly
        case let minutes?: kind = .other(minutes: minutes)
        case nil: kind = .other(minutes: 0)
        }
        let resetsAt = raw["resetsAt"]?.intValue.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return UsageWindow(kind: kind, usedPercent: used, resetsAt: resetsAt)
    }

    private static func credits(from raw: JSONValue?) -> Credits? {
        guard let raw, case .object = raw else { return nil }
        guard case .bool(true)? = raw["hasCredits"] else { return nil }
        var balance: Decimal?
        if case .string(let s)? = raw["balance"] { balance = Decimal(string: s) }
        var unlimited = false
        if case .bool(let u)? = raw["unlimited"] { unlimited = u }
        return Credits(balance: balance, unlimited: unlimited)
    }
}
