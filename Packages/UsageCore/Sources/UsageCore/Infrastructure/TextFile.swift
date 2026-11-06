import Foundation

public enum TextFileError: Error, Sendable, Equatable {
    case notText
    case readFailed(String)
    case writeFailed(String)
}

public struct TextFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() throws(TextFileError) -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if Self.isMissingFile(error) { return nil }
            throw .readFailed(error.localizedDescription)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw .notText }
        return text
    }

    public func write(_ text: String) throws(TextFileError) {
        let manager = FileManager.default
        do {
            let target = try resolvedWriteTarget()
            let parent = target.deletingLastPathComponent()
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            let exists = try Self.attributes(at: target) != nil
            let temporary = parent.appendingPathComponent(".\(UUID().uuidString).tmp")
            do {
                try Data(text.utf8).write(to: temporary, options: .withoutOverwriting)
                if exists {
                    // Default replacement keeps the original file's metadata, including permissions.
                    _ = try manager.replaceItemAt(target, withItemAt: temporary)
                } else {
                    try manager.moveItem(at: temporary, to: target)
                }
            } catch {
                if manager.fileExists(atPath: temporary.path) {
                    try manager.removeItem(at: temporary)
                }
                throw error
            }
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    private func resolvedWriteTarget() throws -> URL {
        var target = url
        var visited = Set<URL>()
        while let attributes = try Self.attributes(at: target),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            guard visited.insert(target.standardizedFileURL).inserted else {
                throw POSIXError(.ELOOP)
            }
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)
            if destination.hasPrefix("/") {
                target = URL(fileURLWithPath: destination)
            } else {
                target = target.deletingLastPathComponent().appendingPathComponent(destination)
            }
        }
        return target
    }

    private static func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            if isMissingFile(error) { return nil }
            throw error
        }
    }

    private static func isMissingFile(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)
    }
}
