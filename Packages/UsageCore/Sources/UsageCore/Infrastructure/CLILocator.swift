import Foundation

public protocol ExecutableProbe: Sendable {
    func isExecutable(atPath path: String) -> Bool
}

public struct FileManagerProbe: ExecutableProbe {
    public init() {}

    public func isExecutable(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

public protocol LoginShellLookup: Sendable {
    func commandPath(for name: String) async -> String?
}

/// Names are interpolated into a shell command, so only a conservative character set is allowed.
private func isSafeCommandName(_ name: String) -> Bool {
    name.wholeMatch(of: /[A-Za-z0-9._-]+/) != nil
}

public struct ZshLoginShellLookup: LoginShellLookup {
    private let runner: any ProcessRunner

    public init(runner: any ProcessRunner) { self.runner = runner }

    public func commandPath(for name: String) async -> String? {
        guard isSafeCommandName(name) else { return nil }
        let runner = self.runner
        do {
            return try await withTimeout(.seconds(5)) {
                try await runner.run(
                    executable: URL(filePath: "/bin/zsh"),
                    arguments: ["-lc", "command -v \(name)"],
                    environment: [:]
                ) { channel in
                    while let line = try await channel.receive() {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("/") { return trimmed }
                    }
                    return nil
                }
            }
        } catch {
            return nil
        }
    }
}

public actor CLILocator {
    private let home: URL
    private let probe: any ExecutableProbe
    private let shell: any LoginShellLookup
    /// Only the (slow) login-shell lookup is cached, misses included; known directories are re-probed every call.
    private var shellCache: [String: String?] = [:]

    public init(home: URL, probe: any ExecutableProbe = FileManagerProbe(), shell: any LoginShellLookup) {
        self.home = home
        self.probe = probe
        self.shell = shell
    }

    public func locate(_ name: String, override: String?) async -> URL? {
        guard isSafeCommandName(name) else { return nil }

        if let override = expandedOverride(override), probe.isExecutable(atPath: override) {
            return URL(filePath: override)
        }
        return await resolve(name)
    }

    private func expandedOverride(_ override: String?) -> String? {
        guard let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        if trimmed == "~" { return home.path }
        if trimmed.hasPrefix("~/") { return home.path + "/" + trimmed.dropFirst(2) }
        return trimmed
    }

    private func resolve(_ name: String) async -> URL? {
        let directories = [
            home.path + "/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        for directory in directories {
            let candidate = directory + "/" + name
            if probe.isExecutable(atPath: candidate) { return URL(filePath: candidate) }
        }
        let shellPath: String?
        if let cached = shellCache[name] {
            shellPath = cached
        } else {
            shellPath = await shell.commandPath(for: name)
            shellCache[name] = .some(shellPath)
        }
        return shellPath.map { URL(filePath: $0) }
    }
}
