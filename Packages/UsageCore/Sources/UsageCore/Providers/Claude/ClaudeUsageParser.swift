import Foundation
import os

/// Maps the `/api/oauth/usage` response to usage windows.
public enum ClaudeUsageParser {
    private static let log = Logger(subsystem: "io.github.vuxng.LLMUsage", category: "claude")

    private static let legacyFields: [(key: String, kind: WindowKind)] = [
        ("five_hour", .session5h),
        ("seven_day", .weekly),
        ("seven_day_opus", .weeklyModel("Opus")),
        ("seven_day_sonnet", .weeklyModel("Sonnet")),
    ]

    public static func windows(from data: Data) throws(UsageError) -> [UsageWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .unexpectedFormat("not a JSON object")
        }
        if let limits = root["limits"] as? [Any] {
            return limits.compactMap { ($0 as? [String: Any]).flatMap(window(fromLimit:)) }
        }
        guard legacyFields.contains(where: { root[$0.key] is [String: Any] }) else {
            throw .unexpectedFormat("no limits or legacy fields")
        }
        return legacyFields.compactMap { field in
            guard let obj = root[field.key] as? [String: Any], let used = number(obj["utilization"]) else { return nil }
            return UsageWindow(kind: field.kind, usedPercent: used, resetsAt: date(obj["resets_at"]))
        }
    }

    private static func window(fromLimit row: [String: Any]) -> UsageWindow? {
        guard (row["is_active"] as? Bool) != false else { return nil }
        let name = row["kind"] as? String ?? "?"
        let kind: WindowKind
        switch name {
        case "session": kind = .session5h
        case "weekly_all": kind = .weekly
        case "weekly_scoped":
            let model = (row["scope"] as? [String: Any])?["model"] as? [String: Any]
            guard let label = (model?["display_name"] as? String) ?? (model?["id"] as? String) else {
                log.notice("skipping weekly_scoped row without model name")
                return nil
            }
            kind = .weeklyModel(label)
        default:
            log.notice("skipping unknown limit kind: \(name, privacy: .public)")
            return nil
        }
        guard let percent = number(row["percent"]) else { return nil }
        return UsageWindow(kind: kind, usedPercent: percent, resetsAt: date(row["resets_at"]))
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber).map(\.doubleValue)
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap(parseISO8601)
    }
}
