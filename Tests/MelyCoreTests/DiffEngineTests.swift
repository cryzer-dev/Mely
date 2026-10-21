// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Testing
import Foundation
@testable import MelyCore

@Suite struct DiffEngineTests {
    @Test func diffs() {

        // ── DiffEngine.fromEdit — additions ───────────────────────────────────
        do {
            let d = DiffEngine.fromEdit(old: "", new: "hello\nworld\n", path: "/a/b.swift")
            #expect(d.added == 2, "added == 2")
            #expect(d.removed == 0, "removed == 0")
            #expect(!d.tooLarge, "!tooLarge")
            #expect(d.hunks.count == 1, "1 hunk")
            #expect(d.name == "b.swift", "name == b.swift")
        }

        // ── DiffEngine.fromEdit — removals ────────────────────────────────────
        do {
            let d = DiffEngine.fromEdit(old: "hello\nworld\n", new: "", path: "/x.py")
            #expect(d.added == 0, "added == 0")
            #expect(d.removed == 2, "removed == 2")
            #expect(d.hunks.count == 1, "1 hunk")
        }

        // ── DiffEngine.fromEdit — replacement ─────────────────────────────────
        do {
            let d = DiffEngine.fromEdit(old: "foo\nbar\nbaz\n",
                                         new: "foo\nqux\nbaz\n",
                                         path: "/f.ts")
            #expect(d.added == 1, "added == 1")
            #expect(d.removed == 1, "removed == 1")
            #expect(d.hunks.first?.lines.contains(where: { $0.kind == .context }) == true, "has context lines")
        }

        // ── DiffEngine.fromNew — new file ──────────────────────────────────────
        do {
            let d = DiffEngine.fromNew(content: "line1\nline2\nline3\n", path: "/new.rs")
            #expect(d.added == 3, "added == 3")
            #expect(d.removed == 0, "removed == 0")
            #expect(d.hunks.flatMap { $0.lines }.allSatisfy { $0.kind == .added }, "all lines .added")
        }

        // ── DiffEngine.fromEdit — MultiEdit (two edits) ────────────────────────
        do {
            let d1 = DiffEngine.fromEdit(old: "aaa\n", new: "bbb\n", path: "/m.kt")
            let d2 = DiffEngine.fromEdit(old: "ccc\n", new: "ddd\n", path: "/m.kt")
            #expect(d1.added == 1, "d1 added == 1")
            #expect(d1.removed == 1, "d1 removed == 1")
            #expect(d2.added == 1, "d2 added == 1")
            #expect(d2.removed == 1, "d2 removed == 1")
        }

        // ── DiffEngine — tooLarge ──────────────────────────────────────────────
        do {
            // Generate > 200 KB combined content
            let bigOld = String(repeating: "x", count: 150 * 1024)
            let bigNew = String(repeating: "y", count: 60 * 1024)
            let d = DiffEngine.fromEdit(old: bigOld, new: bigNew, path: "/big.swift")
            #expect(d.tooLarge, "tooLarge == true")
            #expect(d.hunks.isEmpty, "hunks.isEmpty")
        }

        // ── DiffEngine — CRLF ─────────────────────────────────────────────────
        do {
            let d = DiffEngine.fromEdit(old: "a\r\nb\r\n", new: "a\r\nc\r\n", path: "/win.txt")
            #expect(d.added == 1, "added == 1")
            #expect(d.removed == 1, "removed == 1")
        }

        // ── DiffEngine — no trailing newline ──────────────────────────────────
        do {
            let d = DiffEngine.fromEdit(old: "hello", new: "hello\nworld", path: "/t.txt")
            #expect(d.added == 1, "added == 1")
            #expect(d.removed == 0, "removed == 0")
        }

        // ── DiffEngine — 3-line context ───────────────────────────────────────
        do {
            // 10-line file, change line 5
            let oldContent = (1...10).map { "line\($0)" }.joined(separator: "\n") + "\n"
            let newContent = (1...10).map { $0 == 5 ? "changed" : "line\($0)" }.joined(separator: "\n") + "\n"
            let d = DiffEngine.fromEdit(old: oldContent, new: newContent, path: "/ctx.swift")
            #expect(d.added == 1, "added == 1")
            #expect(d.removed == 1, "removed == 1")
            #expect(d.hunks.count == 1, "1 hunk")
            let hunk = d.hunks[0]
            let contextLines = hunk.lines.filter { $0.kind == .context }
            #expect(contextLines.count >= 3, "has context before change")
        }

        // ── DiffEngine — m*n > 1_000_000 → tooLarge ─────────────────────────
        do {
            // 1001 old lines × 1001 new lines = > 1M
            let many = (0..<1001).map { "line\($0)" }.joined(separator: "\n")
            let d = DiffEngine.fromEdit(old: many, new: many + "\nextra", path: "/big.swift")
            #expect(d.tooLarge, "tooLarge when m*n > 1M")
            #expect(d.hunks.isEmpty, "hunks empty")
        }

        // ── DiffEngine.fromNew — too large ────────────────────────────────────
        do {
            let bigContent = String(repeating: "x\n", count: FileDiff.maxLines + 1)
            let d = DiffEngine.fromNew(content: bigContent, path: "/new.swift")
            #expect(d.tooLarge, "fromNew tooLarge")
            #expect(d.isNewFile, "fromNew isNewFile")
            #expect(d.hunks.isEmpty, "fromNew hunks empty")
            #expect(d.added > 0, "fromNew added > 0")
        }

        // ── DiffEngine.toOneLine ──────────────────────────────────────────────
        do {
            // multi-line joined with space
            #expect(DiffEngine.toOneLine("line one\nline two\nline three") == "line one line two line three", "multi-line joined")

            // bold stripped
            #expect(DiffEngine.toOneLine("**hello** world") == "hello world", "bold stripped")

            // heading stripped
            #expect(DiffEngine.toOneLine("## My Title\nsome text") == "My Title some text", "heading stripped")

            // empty input → empty
            #expect(DiffEngine.toOneLine("").isEmpty, "empty → empty")

            // truncation
            let long = DiffEngine.toOneLine(String(repeating: "x ", count: 200), maxChars: 10)
            #expect(long.count <= 10, "truncated to maxChars")

            // stop at blank line
            #expect(DiffEngine.toOneLine("First para.\n\nSecond para.") == "First para.", "blank line → first para only")

            // stop at --- separator
            #expect(DiffEngine.toOneLine("Done. Single commit 450a657 on github-pulse.\n\n---\n\nFiles touched (7)…")
                    == "Done. Single commit 450a657 on github-pulse.", "--- separator → first para only")

            // stop at *** separator
            #expect(DiffEngine.toOneLine("Summary line.\n***\nMore details.") == "Summary line.", "*** separator → first para only")

            // stop at table row (|)
            #expect(DiffEngine.toOneLine("Result:\n| Col1 | Col2 |\n|---|---|\n| A | B |") == "Result:", "table row → first para only")

            // strip leading bullet -
            #expect(DiffEngine.toOneLine("- item one\n- item two") == "item one item two", "strip bullet -")

            // strip leading bullet *
            #expect(DiffEngine.toOneLine("* first\n* second") == "first second", "strip bullet *")

            // strip ordered list
            #expect(DiffEngine.toOneLine("1. step one\n2. step two") == "step one step two", "strip ordered list")

            // first paragraph empty → fall through to next
            #expect(DiffEngine.toOneLine("\n\nActual content.") == "Actual content.", "empty first para → next")
        }

    }
}
