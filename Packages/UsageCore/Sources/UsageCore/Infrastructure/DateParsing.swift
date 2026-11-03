import Foundation

/// Parses ISO 8601 timestamps with or without fractional seconds (any number of digits)
/// and with either a numeric offset or a `Z` suffix. Returns nil when unparseable.
public func parseISO8601(_ string: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: string) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}
