import Testing
import Foundation
@testable import MelyCore

@Suite struct StepLabelTests {
    static let patch = """
    *** Begin Patch
    *** Update File: src/server.ts
    @@ export function start() {
    -  listen(3000)
    +  listen(port)
    +  log("started")
    *** Add File: src/port.ts
    +export const port = 3000
    *** End Patch
    """

    @Test func codexShellCommands() {
        // Codex sends argv; a `bash -lc` script is what ran.
        #expect(StepLabel.label(tool: "shell", input: ["command": ["bash", "-lc", "npm test"]]) == "Тестирует · npm test")
        #expect(StepLabel.label(tool: "exec_command", input: ["cmd": "rg TODO"]) == "Ищет · rg TODO")
        #expect(StepLabel.label(tool: "shell", input: ["command": ["ls", "-la"]]) == "Ищет · ls -la")
        // Codex may also call its shell `Bash`, like Claude Code.
        #expect(StepLabel.label(tool: "Bash", input: ["command": "cat README.md"]) == "Читает · cat README.md")
    }

    @Test func codexPatch() {
        #expect(StepLabel.label(tool: "apply_patch", input: ["input": Self.patch]) == "Правит · server.ts и ещё 1")
        let one = "*** Begin Patch\n*** Update File: a.swift\n-x\n+y\n*** End Patch"
        #expect(StepLabel.label(tool: "apply_patch", input: ["command": ["apply_patch", one]]) == "Правит · a.swift")
        #expect(StepLabel.label(tool: "apply_patch", input: [:]) == "Правит")
    }

    @Test func codexPatchDiffsPerFile() {
        let diffs = StepLabel.diffs(tool: "apply_patch", input: ["input": Self.patch])
        #expect(diffs.map(\.name) == ["server.ts", "port.ts"])
        #expect(diffs.map(\.added) == [2, 1])
        #expect(diffs.map(\.removed) == [1, 0])
        #expect(diffs.map(\.isNewFile) == [false, true])
        // Claude's tools are unchanged: one diff per call.
        #expect(StepLabel.diffs(tool: "Edit", input: ["file_path": "/w/a.ts", "old_string": "a", "new_string": "b"]).count == 1)
    }

    @Test func codexOtherTools() {
        #expect(StepLabel.label(tool: "update_plan", input: ["plan": []]) == "План")
        #expect(StepLabel.label(tool: "spawn_agent", input: ["message": "Проверь тесты корзины"]) == "Агент · Проверь тесты корзины")
        #expect(StepLabel.label(tool: "view_image", input: ["path": "/tmp/shot.png"]) == "Смотрит картинку · shot.png")
        #expect(StepLabel.label(tool: "web_search", input: ["query": "swift 6 sendable"]) == "Ищет в интернете · swift 6 sendable")
        #expect(StepLabel.label(tool: "mcp__github__create_pr", input: [:]) == "github · create_pr")
    }

    @MainActor @Test func patchCountsInTheSession() {
        let store = SessionStore()
        let origin = HookOrigin(["session_id": "s", "cwd": "/w/api", HookWire.agentKey: "codex"])
        let session = store.apply(.toolFinished(tool: "apply_patch", input: JSONObject(["input": Self.patch]), failed: false),
                                  origin: origin)
        #expect(session?.addedLines == 3)
        #expect(session?.removedLines == 1)
    }
}
