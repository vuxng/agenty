import Foundation
@testable import UsageCore

struct FakeProbe: ExecutableProbe {
    let executables: Set<String>
    func isExecutable(atPath path: String) -> Bool { executables.contains(path) }
}

actor FakeShell: LoginShellLookup {
    private let result: String?
    private(set) var calls = 0

    init(result: String?) { self.result = result }

    func commandPath(for name: String) async -> String? {
        calls += 1
        return result
    }
}
