import SwiftUI

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(languageLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "square.on.square")
                        .font(.system(size: 14))
                        .foregroundStyle(copied ? Theme.success : Theme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(Theme.separator)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(Theme.monoFont(13))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.separator, lineWidth: 1)
        )
    }

    private var languageLabel: String {
        guard let language, !language.isEmpty else { return "Code" }
        let display: [String: String] = [
            "js": "JavaScript", "ts": "TypeScript", "py": "Python",
            "rb": "Ruby", "go": "Go", "rs": "Rust", "kt": "Kotlin",
            "swift": "Swift", "java": "Java", "cpp": "C++", "c": "C",
            "cs": "C#", "sh": "Shell", "bash": "Bash", "zsh": "Zsh",
            "json": "JSON", "yaml": "YAML", "yml": "YAML", "xml": "XML",
            "html": "HTML", "css": "CSS", "sql": "SQL", "md": "Markdown",
            "dockerfile": "Dockerfile", "toml": "TOML",
        ]
        return display[language.lowercased()] ?? language.prefix(1).uppercased() + language.dropFirst()
    }

    // MARK: - Syntax Highlighting

    /// Lightweight keyword highlighting; full syntax trees are overkill on-device.
    private var highlighted: AttributedString {
        var result = AttributedString(code)
        let baseColor = UIColor(white: 0.88, alpha: 1)
        result.foregroundColor = baseColor

        // Unlabeled fences are often prose or tool output, not code — highlighting
        // them mis-colors ordinary words (e.g. "Omsk:" rendered as a type). Render plain.
        guard let language, !language.isEmpty else { return result }

        let keywordColor = UIColor(red: 1.0, green: 0.62, blue: 0.39, alpha: 1)   // Orange
        let stringColor = UIColor(red: 0.6, green: 0.85, blue: 0.55, alpha: 1)    // Green
        let commentColor = UIColor(white: 0.5, alpha: 1)                           // Gray
        let numberColor = UIColor(red: 0.82, green: 0.68, blue: 1.0, alpha: 1)    // Purple
        let typeColor = UIColor(red: 0.55, green: 0.82, blue: 1.0, alpha: 1)      // Light blue

        // Keywords
        let keywords = [
            "func", "let", "var", "if", "else", "for", "while", "return", "import",
            "def", "class", "struct", "enum", "print", "in", "guard", "switch",
            "case", "break", "continue", "do", "throw", "throws", "try", "catch",
            "const", "function", "async", "await", "from", "yield", "export", "default",
            "range", "list", "None", "True", "False", "nil", "null", "true", "false",
            "self", "Self", "super", "this", "new", "delete", "typeof", "instanceof",
            "public", "private", "internal", "static", "final", "override", "protocol",
            "extension", "where", "some", "any", "as", "is", "init", "deinit",
            "type", "interface", "implements", "extends", "abstract", "package",
            "fn", "pub", "mod", "use", "crate", "impl", "trait", "mut", "ref", "move",
            "with", "pass", "elif", "except", "finally", "raise", "lambda", "nonlocal",
        ]
        applyKeywords(keywords, color: keywordColor, to: &result)

        // Numbers: integer and float literals
        applyPattern(#"\b\d+\.?\d*\b"#, color: numberColor, to: &result)

        // Types: PascalCase identifiers (likely type names)
        applyPattern(#"\b[A-Z][a-zA-Z0-9]+\b"#, color: typeColor, to: &result)

        // Strings (single and double quoted)
        applyPattern(#""[^"\n]*"|'[^'\n]*'"#, color: stringColor, to: &result)

        // Comments (# and // style)
        applyPattern(#"(?m)(#|//).*$"#, color: commentColor, to: &result)

        return result
    }

    private func applyKeywords(_ keywords: [String], color: UIColor, to result: inout AttributedString) {
        let text = code as NSString
        for keyword in keywords {
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.location < text.length {
                let found = text.range(of: "\\b\(keyword)\\b", options: .regularExpression, range: searchRange)
                if found.location == NSNotFound { break }
                if let swiftRange = Range(found, in: code) {
                    let lowerOffset = code.distance(from: code.startIndex, to: swiftRange.lowerBound)
                    let lower = result.index(result.startIndex, offsetByCharacters: lowerOffset)
                    let upper = result.index(lower, offsetByCharacters: keyword.count)
                    result[lower..<upper].foregroundColor = color
                }
                searchRange = NSRange(location: found.location + found.length, length: text.length - found.location - found.length)
            }
        }
    }

    private func applyPattern(_ pattern: String, color: UIColor, to result: inout AttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: code, range: NSRange(code.startIndex..., in: code))
        for match in matches {
            guard let range = Range(match.range, in: code) else { continue }
            let lowerOffset = code.distance(from: code.startIndex, to: range.lowerBound)
            let length = code.distance(from: range.lowerBound, to: range.upperBound)
            let lower = result.index(result.startIndex, offsetByCharacters: lowerOffset)
            let upper = result.index(lower, offsetByCharacters: length)
            result[lower..<upper].foregroundColor = color
        }
    }
}
