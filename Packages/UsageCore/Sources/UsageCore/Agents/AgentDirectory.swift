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

    public func files() -> [URL]? {
        let manager = FileManager.default
        let target = url.resolvingSymlinksInPath()
        guard (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        var files: [URL] = []
        func visit(_ target: URL, original: URL, ancestors: Set<String>) {
            guard !ancestors.contains(target.path) else { return }
            let ancestors = ancestors.union([target.path])
            let children: [URL]
            if recursive {
                guard let enumerator = manager.enumerator(at: target, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else { return }
                children = enumerator.allObjects.compactMap { $0 as? URL }
            } else {
                children = (try? manager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
            }
            for child in children {
                let resolved = child.resolvingSymlinksInPath()
                let originalChild = original.appendingPathComponent(child.lastPathComponent)
                guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { continue }
                if values.isRegularFile == true, child.pathExtension == fileExtension {
                    files.append(originalChild)
                } else if recursive, values.isDirectory == true {
                    visit(resolved, original: originalChild, ancestors: ancestors)
                }
            }
        }
        visit(target, original: url, ancestors: [])
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
