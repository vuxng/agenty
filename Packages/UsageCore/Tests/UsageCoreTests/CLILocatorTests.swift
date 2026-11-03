import Foundation
import Testing
@testable import UsageCore

struct CLILocatorTests {
    let home = URL(filePath: "/Users/test")

    private func locator(_ executables: Set<String> = [], shell: FakeShell) -> CLILocator {
        CLILocator(home: home, probe: FakeProbe(executables: executables), shell: shell)
    }

    @Test func overrideWinsWhenExecutable() async {
        let l = locator(["/Users/test/bin/codex", "/opt/homebrew/bin/codex"], shell: FakeShell(result: nil))
        let url = await l.locate("codex", override: "~/bin/codex")
        #expect(url?.path == "/Users/test/bin/codex")
    }

    @Test func invalidOverrideFallsThrough() async {
        let l = locator(["/opt/homebrew/bin/codex"], shell: FakeShell(result: nil))
        let url = await l.locate("codex", override: "/nope/codex")
        #expect(url?.path == "/opt/homebrew/bin/codex")
    }

    @Test func blankOverrideCountsAsNone() async {
        let l = locator(["/opt/homebrew/bin/codex"], shell: FakeShell(result: nil))
        let url = await l.locate("codex", override: "   ")
        #expect(url?.path == "/opt/homebrew/bin/codex")
    }

    @Test func tildeAloneExpandsToHome() async {
        let l = locator(["/Users/test"], shell: FakeShell(result: nil))
        let url = await l.locate("codex", override: "~")
        #expect(url?.path == "/Users/test")
    }

    @Test func overrideIsCheckedOnEveryCall() async {
        let l = locator(["/opt/homebrew/bin/codex", "/x/codex"], shell: FakeShell(result: nil))
        #expect(await l.locate("codex", override: nil)?.path == "/opt/homebrew/bin/codex")
        #expect(await l.locate("codex", override: "/x/codex")?.path == "/x/codex")
        #expect(await l.locate("codex", override: nil)?.path == "/opt/homebrew/bin/codex")
    }

    @Test func knownDirectoriesInOrder() async {
        let l = locator(["/opt/homebrew/bin/codex", "/Users/test/.local/bin/codex"], shell: FakeShell(result: nil))
        let url = await l.locate("codex", override: nil)
        #expect(url?.path == "/Users/test/.local/bin/codex")
    }

    @Test func grokBinDirectoryIsSearched() async {
        let l = locator(["/Users/test/.grok/bin/grok"], shell: FakeShell(result: nil))
        let url = await l.locate("grok", override: nil)
        #expect(url?.path == "/Users/test/.grok/bin/grok")
    }

    @Test func loginShellUsedLastAndCached() async {
        let shell = FakeShell(result: "/custom/codex")
        let l = locator(shell: shell)
        #expect(await l.locate("codex", override: nil)?.path == "/custom/codex")
        #expect(await l.locate("codex", override: nil)?.path == "/custom/codex")
        #expect(await shell.calls == 1)
    }

    @Test func missIsCached() async {
        let shell = FakeShell(result: nil)
        let l = locator(shell: shell)
        #expect(await l.locate("codex", override: nil) == nil)
        #expect(await l.locate("codex", override: nil) == nil)
        #expect(await shell.calls == 1)
    }

    @Test func rejectsUnsafeNames() async {
        let shell = FakeShell(result: "/custom/codex")
        let l = locator(shell: shell)
        #expect(await l.locate("codex; rm -rf ~", override: nil) == nil)
        #expect(await l.locate("", override: nil) == nil)
        #expect(await shell.calls == 0)
    }

    @Test func zshLookupReturnsFirstAbsoluteLine() async {
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: ["some banner", "  /Users/test/.local/bin/codex  "]))
        let path = await ZshLoginShellLookup(runner: runner).commandPath(for: "codex")
        #expect(path == "/Users/test/.local/bin/codex")
        #expect(runner.arguments == ["-lc", "command -v codex"])
        #expect(runner.executable == URL(filePath: "/bin/zsh"))
        #expect(runner.environment.isEmpty)
    }

    @Test func zshLookupRefusesUnsafeName() async {
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: ["/x"]))
        let path = await ZshLoginShellLookup(runner: runner).commandPath(for: "a;b")
        #expect(path == nil)
        #expect(runner.runCount == 0)
    }
}
