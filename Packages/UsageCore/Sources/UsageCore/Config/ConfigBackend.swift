public protocol ConfigBackend: Sendable {
    var provider: ProviderID { get }
    var file: TextFile { get }
    func load() async throws(ConfigError) -> ConfigSnapshot
    func save(_ edits: [ConfigEdit], version: String?) async throws(ConfigError) -> ConfigSaveResult
    func validate(_ text: String) async throws(ConfigError) -> ConfigValidation
    func writeFile(_ text: String) async throws(ConfigError)
}

extension ConfigBackend {
    public var displayPath: String { "~/.\(provider.rawValue)/\(file.url.lastPathComponent)" }
}
