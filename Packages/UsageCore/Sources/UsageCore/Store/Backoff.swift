public enum Backoff {
    /// `min(60s * 2^(n-1), cap)`; zero when there were no failures.
    public static func delay(afterFailures n: Int, cap: Duration) -> Duration {
        guard n > 0 else { return .zero }
        let exponent = min(n - 1, 20) // keeps the multiplier far from overflow
        return min(.seconds(60) * (1 << exponent), cap)
    }
}
