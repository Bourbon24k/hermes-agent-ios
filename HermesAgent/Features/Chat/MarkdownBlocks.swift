import Foundation

/// A single list item with optional ordering.
struct ListItem: Identifiable, Hashable {
    let id: Int
    let content: String
    let ordered: Bool
    let index: Int       // 1-based for ordered lists, 0 for unordered
}

/// Splits markdown into renderable blocks: prose, fenced code, headings, lists, blockquotes, dividers.
enum MarkdownBlock: Identifiable, Hashable {
    case text(id: Int, content: String)
    case code(id: Int, language: String?, content: String)
    case heading(id: Int, level: Int, content: String)
    case listBlock(id: Int, items: [ListItem])
    case blockquote(id: Int, content: String)
    case divider(id: Int)

    var id: Int {
        switch self {
        case .text(let id, _): return id
        case .code(let id, _, _): return id
        case .heading(let id, _, _): return id
        case .listBlock(let id, _): return id
        case .blockquote(let id, _): return id
        case .divider(let id): return id
        }
    }

    // MARK: - Parser

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentText: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var inCode = false
        var nextId = 0

        // Pending list items collected while scanning consecutive list lines.
        var pendingListItems: [ListItem] = []
        var listItemId = 0

        // Pending blockquote lines.
        var pendingQuoteLines: [String] = []

        func makeId() -> Int { defer { nextId += 1 }; return nextId }

        func flushText() {
            let text = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.text(id: makeId(), content: text))
            }
            currentText = []
        }

        func flushCode() {
            let code = codeLines.joined(separator: "\n")
            blocks.append(.code(id: makeId(), language: codeLanguage, content: code))
            codeLines = []
            codeLanguage = nil
        }

        func flushList() {
            guard !pendingListItems.isEmpty else { return }
            blocks.append(.listBlock(id: makeId(), items: pendingListItems))
            pendingListItems = []
        }

        func flushQuote() {
            guard !pendingQuoteLines.isEmpty else { return }
            let body = pendingQuoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                blocks.append(.blockquote(id: makeId(), content: body))
            }
            pendingQuoteLines = []
        }

        func flushAll() {
            flushList()
            flushQuote()
            flushText()
        }

        let lines = markdown.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Fenced code blocks ---
            if trimmed.hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushAll()
                    let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }

            // --- Dividers ---
            if isDivider(trimmed) {
                flushAll()
                blocks.append(.divider(id: makeId()))
                continue
            }

            // --- Headings ---
            if let (level, content) = parseHeading(trimmed) {
                flushAll()
                blocks.append(.heading(id: makeId(), level: level, content: content))
                continue
            }

            // --- Blockquotes ---
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                if !pendingListItems.isEmpty { flushList() }
                if !currentText.isEmpty { flushText() }
                let quoteContent = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                pendingQuoteLines.append(quoteContent)
                continue
            } else if !pendingQuoteLines.isEmpty {
                flushQuote()
            }

            // --- List items ---
            if let item = parseListItem(trimmed) {
                if !pendingQuoteLines.isEmpty { flushQuote() }
                if !currentText.isEmpty { flushText() }
                pendingListItems.append(ListItem(
                    id: listItemId,
                    content: item.content,
                    ordered: item.ordered,
                    index: item.ordered ? pendingListItems.count + 1 : 0
                ))
                listItemId += 1
                continue
            } else if !pendingListItems.isEmpty {
                // Non-list line after list items — flush the list.
                flushList()
            }

            // --- Regular text ---
            currentText.append(line)
        }

        // Flush remaining.
        if inCode { flushCode() }
        flushAll()
        return blocks
    }

    // MARK: - Line classifiers

    private static func isDivider(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let clean = trimmed.replacingOccurrences(of: " ", with: "")
        return clean.allSatisfy({ $0 == "-" }) ||
               clean.allSatisfy({ $0 == "*" }) ||
               clean.allSatisfy({ $0 == "_" })
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, content: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        // Heading must have a space after the #'s (or be just #'s for an empty heading).
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        let content = rest.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s*#+\s*$"#, with: "", options: .regularExpression) // Remove trailing #'s
        return (level, content)
    }

    private struct ParsedListItem {
        let content: String
        let ordered: Bool
    }

    private static func parseListItem(_ trimmed: String) -> ParsedListItem? {
        // Unordered: "- text", "* text", "+ text"
        if (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")) && trimmed.count > 2 {
            return ParsedListItem(content: String(trimmed.dropFirst(2)), ordered: false)
        }
        // Ordered: "1. text", "2. text", etc.
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let prefix = trimmed[trimmed.startIndex..<dotIndex]
            if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
                let afterDot = trimmed[trimmed.index(after: dotIndex)...]
                if afterDot.hasPrefix(" ") {
                    return ParsedListItem(content: String(afterDot.dropFirst()), ordered: true)
                }
            }
        }
        return nil
    }
}

extension AttributedString {
    /// Markdown rendering tolerant of partial/streaming content.
    static func hermesMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
