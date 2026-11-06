import Observation

@Observable @MainActor
public final class InstructionsDocument {
    public let file: InstructionsFile
    public var draft = ""
    public private(set) var fileExists = false
    public private(set) var hasConflict = false
    public private(set) var loadError: InstructionsError?
    public private(set) var saveError: InstructionsError?
    public private(set) var isOverridden = false

    // A missing file is distinct from an existing, empty file.
    private var original: String?

    public var isDirty: Bool { draft != (original ?? "") }

    public init(file: InstructionsFile) {
        self.file = file
    }

    public func refresh() {
        isOverridden = file.isOverridden
        do {
            let disk = try file.read()
            fileExists = disk != nil
            loadError = nil
            if disk == original {
                hasConflict = false
            } else if isDirty {
                hasConflict = true
            } else {
                original = disk
                draft = disk ?? ""
                hasConflict = false
            }
        } catch {
            loadError = error
        }
    }

    public func save() {
        refresh()
        guard !hasConflict, loadError == nil else { return }
        do {
            try file.write(draft)
            original = draft
            fileExists = true
            saveError = nil
        } catch {
            saveError = error
        }
    }

    public func revert() {
        draft = original ?? ""
        saveError = nil
    }

    public func keepMine() {
        isOverridden = file.isOverridden
        do {
            let disk = try file.read()
            original = disk
            fileExists = disk != nil
            loadError = nil
            hasConflict = false
        } catch {
            loadError = error
        }
    }

    public func reload() {
        keepMine()
        guard loadError == nil else { return }
        revert()
    }
}
