import Foundation

/// Maps the `result` of `_x.ai/billing` to a `UsageSnapshot`.
public enum GrokBillingMapper {
    public static func snapshot(from result: Data, fetchedAt: Date) throws(UsageError) -> UsageSnapshot {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: result),
              case .object = root else {
            throw .unexpectedFormat("grok result is not a JSON object")
        }
        // The views convert this to Int, which traps on a value that doesn't fit.
        guard case .number(let used)? = root["config"]?["creditUsagePercent"],
              used >= 0, Int(exactly: used.rounded()) != nil else {
            throw .unexpectedFormat("grok config has no creditUsagePercent")
        }
        let period = root["config"]?["currentPeriod"]
        guard case .string(let end)? = period?["end"], let resetsAt = parseISO8601(end) else {
            throw .unexpectedFormat("grok currentPeriod has no valid end")
        }
        let kind: WindowKind = period?["type"] == .string("USAGE_PERIOD_TYPE_WEEKLY") ? .weekly : .billingPeriod
        var plan: String?
        if case .string(let tier)? = root["subscription_tier"], !tier.isEmpty { plan = tier }
        return UsageSnapshot(provider: .grok, plan: plan,
                             windows: [UsageWindow(kind: kind, usedPercent: used, resetsAt: resetsAt)],
                             credits: nil, fetchedAt: fetchedAt)
    }
}
