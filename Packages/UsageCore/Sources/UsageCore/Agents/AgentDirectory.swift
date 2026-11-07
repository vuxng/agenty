import Foundation

public struct AgentDirectory: Sendable {
    public let url: URL
    public let home: URL
    public let fileExtension: String
    public let recursive: Bool

    public init(url: URL, home: URL, fileExtension: String, recursive: Bool) {
        self.url = url
        self.home = home
        self.fileExtension = fileExtension
        self.recursive = recursive
    }

    public func files() throws(AgentLoadError) -> [URL]? {
        let manager = FileManager.default
        let target = url.resolvingSymlinksInPath()
        do {
            guard try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { return nil }
        } catch {
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain,
               cocoa.code == NSFileReadNoSuchFileError || cocoa.code == NSFileNoSuchFileError {
                return nil
            }
            throw .failed(String(describing: error))
        }
        var files: [URL] = []
        func visit(_ target: URL, original: URL, ancestors: Set<String>) throws {
            guard !ancestors.contains(target.path) else { return }
            let ancestors = ancestors.union([target.path])
            let children: [URL]
            if recursive {
                var enumerationError: (any Error)?
                guard let enumerator = manager.enumerator(at: target, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
                                                          errorHandler: { _, error in
                    if enumerationError == nil { enumerationError = error }
                    return false
                }) else {
                    throw AgentLoadError.failed("Unable to enumerate directory: " + target.path)
                }
                children = enumerator.allObjects.compactMap { $0 as? URL }
                if let enumerationError { throw enumerationError }
            } else {
                children = try manager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])
            }
            for child in children {
                let resolved = child.resolvingSymlinksInPath()
                let originalChild = original.appendingPathComponent(child.lastPathComponent)
                guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else {
                    if child.pathExtension == fileExtension { files.append(originalChild) }
                    continue
                }
                if values.isRegularFile == true, child.pathExtension == fileExtension {
                    files.append(originalChild)
                } else if recursive, values.isDirectory == true {
                    try visit(resolved, original: originalChild, ancestors: ancestors)
                }
            }
        }
        do {
            try visit(target, original: url, ancestors: [])
        } catch {
            throw .failed(String(describing: error))
        }
        return files.sorted { $0.path < $1.path }
    }

    public func displayPath(of url: URL) -> String {
        let path = url.path
        let prefix = home.path
        if path == prefix { return "~" }
        let boundary = prefix.hasSuffix("/") ? prefix : prefix + "/"
        guard path.hasPrefix(boundary) else { return path }
        return "~/" + path.dropFirst(boundary.count)
    }
}
