import Testing
@testable import MelyCore

@Suite struct SessionHostTests {
    func origin(_ p: [String: Any]) -> HookOrigin { HookOrigin(p) }

    @Test func webStormFromProcessTree() {
        let host = SessionHost.resolve(origin(["host_bundle_id": "com.jetbrains.WebStorm",
                                               "terminal_emulator": "JetBrains-JediTerm"]))
        #expect(host == SessionHost(bundleId: "com.jetbrains.WebStorm", name: "WebStorm", family: .jetbrains))
    }

    @Test func webStormEAPAndOtherIDEs() {
        #expect(SessionHost.resolve(origin(["host_bundle_id": "com.jetbrains.WebStorm-EAP"])).name == "WebStorm")
        #expect(SessionHost.resolve(origin(["bundle_id": "com.jetbrains.pycharm"])).name == "PyCharm")
        #expect(SessionHost.resolve(origin(["host_bundle_id": "com.google.android.studio"])).family == .jetbrains)
        #expect(SessionHost.resolve(origin(["host_bundle_id": "com.jetbrains.newide"])).name == "JetBrains IDE")
    }

    @Test func jetBrainsByTerminalEmulatorAlone() {
        let host = SessionHost.resolve(origin(["terminal_emulator": "JetBrains-JediTerm"]))
        #expect(host.family == .jetbrains && host.name == "JetBrains IDE" && host.bundleId == nil)
    }

    @Test func terminalsAndEditors() {
        #expect(SessionHost.resolve(origin(["term_program": "iTerm.app"])).name == "iTerm")
        #expect(SessionHost.resolve(origin(["term_program": "Apple_Terminal"])).bundleId == "com.apple.Terminal")
        #expect(SessionHost.resolve(origin(["term_program": "vscode"])).family == .vscode)
        #expect(SessionHost.resolve(origin(["host_bundle_id": "com.todesktop.230313mzl4w4u92", "term_program": "vscode"])).name == "Cursor")
        // cmux sets TERM_PROGRAM=ghostty: the bundle id decides.
        #expect(SessionHost.resolve(origin(["term_program": "ghostty", "host_bundle_id": "com.cmuxterm.app"])).name == "cmux")
    }

    @Test func unknownHostIsShownNotDropped() {
        let host = SessionHost.resolve(origin(["host_bundle_id": "com.example.weird"]))
        #expect(host == SessionHost(bundleId: "com.example.weird", name: "Терминал", family: .unknown))
        #expect(SessionHost.resolve(origin([:])).name == "Терминал")
    }
}

@Suite struct ProjectRootTests {
    @Test func walksUpToIdeaFolder() {
        let existing: Set = ["/Users/me/work/shop/.idea", "/Users/me/work/.git"]
        let root = ProjectRoot.find(from: "/Users/me/work/shop/src/cart", markers: [".idea", ".git"],
                                    stop: "/Users/me", exists: existing.contains)
        #expect(root == "/Users/me/work/shop")
    }

    @Test func fallsBackToGitThenCwd() {
        let git: Set = ["/Users/me/work/api/.git"]
        #expect(ProjectRoot.find(from: "/Users/me/work/api/pkg", markers: [".idea", ".git"],
                                 stop: "/Users/me", exists: git.contains) == "/Users/me/work/api")
        #expect(ProjectRoot.find(from: "/Users/me/notes", markers: [".idea"], stop: "/Users/me",
                                 exists: { _ in false }) == "/Users/me/notes")
    }

    @Test func neverClimbsToHome() {
        let home: Set = ["/Users/me/.idea"]
        #expect(ProjectRoot.find(from: "/Users/me/scratch", markers: [".idea"], stop: "/Users/me",
                                 exists: home.contains) == "/Users/me/scratch")
    }

    @Test func claudeDesktopLocalSession() {
        let host = SessionHost.resolve(HookOrigin(["session_id": "d", "host_bundle_id": "com.anthropic.claudefordesktop"]))
        #expect(host.name == "Claude")
        #expect(host.bundleId == "com.anthropic.claudefordesktop")
    }

    @Test func claudeDesktopByEntrypoint() {
        // The process tree may show only a helper or nothing useful: the entrypoint decides.
        let host = SessionHost.resolve(HookOrigin(["session_id": "d", "claude_entrypoint": "claude-desktop",
                                                   "host_bundle_id": "com.apple.Terminal"]))
        #expect(host.name == "Claude")
    }
}
