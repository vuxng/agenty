import Foundation

public struct CodexAgentSource: AgentSource {
    public let provider: ProviderID = .codex
    public let directory: AgentDirectory
    private let server: CodexAppServer

    public init(locator: CLILocator, pathOverride: @escaping @Sendable () -> String?, runner: any ProcessRunner,
                clientVersion: String, home: URL, timeout: Duration = .seconds(15)) {
        self.directory = AgentDirectory(url: home.appendingPathComponent(".codex/agents"), home: home,
                                        fileExtension: "toml", recursive: true)
        self.server = CodexAppServer(locator: locator, pathOverride: pathOverride, runner: runner,
                                    clientVersion: clientVersion, home: home, timeout: timeout)
    }

    public func load() async throws(AgentLoadError) -> AgentListing {
        guard let files = try directory.files() else { return AgentListing(folderExists: false, agents: []) }
        guard !files.isEmpty else { return AgentListing(folderExists: true, agents: []) }
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent("agenty-agents-" + UUID().uuidString)
        var temporaryCreated = false
        let result: Result<AgentListing, AgentLoadError>
        do {
            try manager.createDirectory(at: temporary, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            temporaryCreated = true
            let listing = try await server.withSession(environment: ["CODEX_HOME": temporary.path]) { rpc in
                var agents: [AgentDefinition] = []
                for url in files {
                    try Task.checkCancellation()
                    let text: String
                    do {
                        guard let contents = try TextFile(url: url).read() else { continue }
                        text = contents
                    } catch {
                        let mapped: AgentReadError
                        switch error {
                        case TextFileError.notText: mapped = .notText
                        case TextFileError.readFailed(let message): mapped = .failed(message)
                        default: mapped = .failed(String(describing: error))
                        }
                        agents.append(.unreadable(url: url, error: mapped))
                        continue
                    }
                    do {
                        let config = temporary.appendingPathComponent("config.toml")
                        try Data(text.utf8).write(to: config)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
                        let response = try await rpc.callOrdered("config/read", params: .object(["includeLayers": .bool(true)]))
                        if let agent = Self.agent(from: response, url: url) { agents.append(agent) }
                    } catch JSONRPCError.server(_, let message, _) {
                        agents.append(.unreadable(url: url, error: .failed(Self.sanitized(
                            message, temporary: temporary, agent: url))))
                    } catch {
                        throw AgentLoadError.failed(Self.sanitized(String(describing: error),
                                                                  temporary: temporary, agent: url))
                    }
                }
                return AgentListing(folderExists: true, agents: agents)
            }
            result = .success(listing)
        } catch CodexAppServerError.cliNotFound {
            result = .failure(.cliNotFound)
        } catch let error as AgentLoadError {
            result = .failure(error)
        } catch {
            result = .failure(.failed(Self.sanitized(String(describing: error), temporary: temporary)))
        }
        if temporaryCreated {
            do { try manager.removeItem(at: temporary) }
            catch {
                var message = "Failed to remove temporary configuration: "
                    + Self.sanitized(String(describing: error), temporary: temporary)
                if case .failure(let loadError) = result { message += "\nLoad failed: \(loadError)" }
                throw .failed(message)
            }
        }
        return try result.get()
    }

    private static func agent(from response: OrderedJSON, url: URL) -> AgentDefinition? {
        guard case .array(let layers) = response.value(at: ["layers"]),
              let user = layers.first(where: { $0.value(at: ["name", "type"]) == .string("user") }),
              case .object(let members) = user.value(at: ["config"]) else { return nil }
        func string(_ key: String) -> String? {
            guard case .string(let text) = members.first(where: { $0.key == key })?.value else { return nil }
            return text
        }
        guard let name = string("name")?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let model = string("model")
        let prompt = string("developer_instructions")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = members.compactMap { member -> AgentField? in
            guard !["name", "description", "model", "developer_instructions"].contains(member.key),
                  let value = fieldValue(member.value) else { return nil }
            return AgentField(key: member.key, value: value)
        }
        return AgentDefinition(url: url, name: name, description: string("description"),
                               model: model == "inherit" ? nil : model, fields: fields,
                               prompt: prompt?.isEmpty == false ? prompt : nil)
    }

    private static func fieldValue(_ value: OrderedJSON) -> AgentFieldValue? {
        switch value {
        case .null: return nil
        case .string(let text):
            return text.rangeOfCharacter(from: .newlines) == nil ? .text(text) : .block(text)
        case .number(let literal): return .text(literal)
        case .bool(let flag): return .text(flag ? "true" : "false")
        case .array(let values):
            let scalars = values.compactMap { value -> String? in
                guard case .text(let text) = fieldValue(value) else { return nil }
                // Nested arrays must remain structured even when their elements are simple.
                if case .array = value { return nil }
                return text
            }
            if scalars.count == values.count { return .text(scalars.joined(separator: ", ")) }
            return .block(String(value.serialized().dropLast()))
        case .object: return .block(String(value.serialized().dropLast()))
        }
    }

    private static func sanitized(_ message: String, temporary: URL, agent: URL? = nil) -> String {
        let paths = [temporary.path, temporary.resolvingSymlinksInPath().path]
            .sorted { $0.count > $1.count }
        var message = message
        if let agent {
            for path in paths {
                message = message.replacingOccurrences(of: path + "/config.toml", with: agent.lastPathComponent)
            }
        }
        for path in paths { message = message.replacingOccurrences(of: path + "/", with: "") }
        return message
    }
}
