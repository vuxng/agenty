import Observation

public enum ConfigMode: Sendable { case controls, file }
public enum ConfigNotice: Sendable, Equatable { case effortReset, fileNotChecked, overridden(String) }

@Observable @MainActor
public final class ConfigDocument {
    public let backend: any ConfigBackend
    public private(set) var mode: ConfigMode = .controls
    public private(set) var config: AgentConfig?
    public private(set) var edits: [ConfigEdit] = []
    public private(set) var diskText: String?
    public var fileDraft = ""
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var hasConflict = false
    public private(set) var loadError: ConfigError?
    public private(set) var saveError: ConfigError?
    public private(set) var notice: ConfigNotice?

    private var version: String?
    private var hasLoaded = false
    private var isRefreshing = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    public var isDirty: Bool {
        switch mode {
        case .controls: !edits.isEmpty
        case .file: fileDraft != (diskText ?? "")
        }
    }

    public var dangerousEdits: [ConfigEdit] {
        edits.filter { edit in
            guard let value = edit.value,
                  let choice = config?.choices.first(where: { $0.path == edit.path }) else { return false }
            return choice.dangerous.contains(value)
                && !equivalent(value, config?.values[edit.path], at: edit.path)
        }
    }

    public var currentModel: ModelOption? {
        guard let model = config?.model else { return nil }
        guard let value = value(at: model.path) else { return model.options.first(where: \.isDefault) }
        guard case .string(let id) = value else { return nil }
        return model.options.first { $0.id == id }
    }

    public var isFastAvailable: Bool {
        guard let fast = config?.fast else { return false }
        return !fast.requiresModelTier || currentModel?.fastDescription != nil
    }

    public init(backend: any ConfigBackend) {
        self.backend = backend
    }

    public func value(at path: ConfigPath) -> ConfigValue? {
        if let edit = edits.first(where: { $0.path == path }) { return edit.value }
        return config?.values[path]
    }

    public func set(_ value: ConfigValue?, at path: ConfigPath) {
        edits.removeAll { $0.path == path }
        if !equivalent(value, config?.values[path], at: path) {
            edits.append(ConfigEdit(path: path, value: value))
        }
    }

    public func selectModel(_ id: String?) {
        notice = nil
        guard let config else { return }
        set(id.map(ConfigValue.string), at: config.model.path)
        guard let efforts = currentModel?.efforts else { return }
        for setting in config.efforts where setting.levels == nil {
            if case .string(let level) = value(at: setting.path), !efforts.contains(level) {
                set(nil, at: setting.path)
                notice = .effortReset
            }
        }
    }

    public func levels(for setting: EffortSetting) -> [String] {
        var levels = setting.levels ?? currentModel?.efforts ?? []
        if case .string(let level) = value(at: setting.path), !levels.contains(level) {
            levels.append(level)
        }
        return levels
    }

    public func switchMode(to mode: ConfigMode) -> Bool {
        guard !isDirty else { return false }
        self.mode = mode
        return true
    }

    public func refresh(force: Bool = false) async {
        guard !isSaving, !isRefreshing else { return }
        let text: String?
        do { text = try readFile() }
        catch {
            loadError = error
            return
        }
        let dirty = isDirty
        if text != diskText, dirty {
            hasConflict = true
            return
        }
        hasConflict = false
        guard text != diskText || force || !hasLoaded else { return }
        diskText = text
        if !dirty { fileDraft = text ?? "" }
        await load()
    }

    public func save() async {
        while isRefreshing {
            await withCheckedContinuation { refreshWaiters.append($0) }
        }
        notice = nil
        guard !isSaving else { return }
        saveError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let savedNotice: ConfigNotice?
            switch mode {
            case .controls:
                if let loadError {
                    saveError = loadError
                    return
                }
                let submittedEdits = edits
                let result = try await backend.save(submittedEdits, version: version)
                edits.removeAll { submittedEdits.contains($0) }
                diskText = try readFile()
                savedNotice = result.overrideMessage.map(ConfigNotice.overridden)
            case .file:
                guard try readFile() == diskText else {
                    hasConflict = true
                    return
                }
                let text = fileDraft
                let validation = try await backend.validate(text)
                guard try readFile() == diskText else {
                    hasConflict = true
                    return
                }
                try await backend.writeFile(text)
                diskText = text
                savedNotice = validation == .unchecked ? .fileNotChecked : nil
            }
            isSaving = false
            await refresh(force: true)
            notice = savedNotice
        } catch {
            if error == .conflict { hasConflict = true }
            else { saveError = error }
        }
    }

    public func revert() {
        notice = nil
        edits.removeAll()
        fileDraft = diskText ?? ""
        saveError = nil
    }

    public func keepMine() async {
        guard !isSaving, !isRefreshing else { return }
        do { diskText = try readFile() }
        catch {
            loadError = error
            return
        }
        await load()
        hasConflict = false
    }

    public func reload() async {
        notice = nil
        guard !isSaving, !isRefreshing else { return }
        edits.removeAll()
        hasConflict = false
        fileDraft = diskText ?? ""
        saveError = nil
        await refresh(force: true)
    }

    private func equivalent(_ lhs: ConfigValue?, _ rhs: ConfigValue?, at path: ConfigPath) -> Bool {
        let aliases = config?.choices.first(where: { $0.path == path })?.unsetAliases ?? []
        let left = lhs.flatMap { aliases.contains($0) ? nil : $0 }
        let right = rhs.flatMap { aliases.contains($0) ? nil : $0 }
        return left == right
    }

    private func readFile() throws(ConfigError) -> String? {
        do { return try backend.file.read() }
        catch { throw .readFailed(String(describing: error)) }
    }

    private func load() async {
        isRefreshing = true
        isLoading = config == nil
        defer {
            isRefreshing = false
            isLoading = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        hasLoaded = true
        do {
            let snapshot = try await backend.load()
            config = snapshot.config
            version = snapshot.version
            loadError = nil
        } catch {
            loadError = error
        }
    }
}
