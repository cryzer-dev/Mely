import Foundation

/// Block-level Markdown for chat answers. Inline marks (bold, code, links) are left in
/// the text for `AttributedString(markdown:)`; it does not lay out blocks itself.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// `ordered` items carry their number; `indent` is the nesting level.
    case listItem(ordered: Int?, indent: Int, text: String)
    case code(language: String?, text: String)
    case quote(String)
    case rule
}

public enum ChatMarkdown {
    /// Parses as much as has arrived: an unclosed code fence (still streaming) is a code block.
    public static func blocks(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: (language: String?, lines: [String])?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))) }
            quote = []
        }

        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if var open = code {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    open.lines.append(raw)
                    code = open
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flushParagraph(); flushQuote()
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                code = (lang.isEmpty ? nil : lang, [])
                continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()
            if trimmed.isEmpty { flushParagraph(); continue }
            if let heading = heading(trimmed) { flushParagraph(); blocks.append(heading); continue }
            if trimmed.count >= 3, Set(trimmed.replacingOccurrences(of: " ", with: "")).count == 1,
               let c = trimmed.first, "-*_".contains(c) {
                flushParagraph(); blocks.append(.rule); continue
            }
            if let item = listItem(raw) { flushParagraph(); blocks.append(item); continue }
            paragraph.append(trimmed)
        }
        if let open = code { blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"))) }
        flushParagraph(); flushQuote()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ raw: String) -> MarkdownBlock? {
        let spaces = raw.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let line = raw.drop { $0 == " " || $0 == "\t" }
        let indent = spaces / 2
        if let marker = line.first, "-*+".contains(marker), line.dropFirst().first == " " {
            return .listItem(ordered: nil, indent: indent, text: String(line.dropFirst(2)))
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, let n = Int(digits) {
            let rest = line.dropFirst(digits.count)
            if let dot = rest.first, dot == "." || dot == ")", rest.dropFirst().first == " " {
                return .listItem(ordered: n, indent: indent, text: String(rest.dropFirst(2)))
            }
        }
        return nil
    }
}
