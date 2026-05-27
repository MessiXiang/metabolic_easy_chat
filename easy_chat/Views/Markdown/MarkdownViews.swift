import SwiftUI
import AppKit

struct MarkdownMessageText: View {
    let text: String
    let isStreaming: Bool
    @State private var parsedText: String
    @State private var parsedBlocks: [MarkdownBlock]
    @State private var pendingParse: DispatchWorkItem?

    init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
        let initialText = isStreaming ? MarkdownStreamingBuffer.renderablePrefix(text) : text
        _parsedText = State(initialValue: initialText)
        _parsedBlocks = State(initialValue: MarkdownBlock.parse(initialText))
    }

    var body: some View {
        Group {
            if MarkdownInlineRenderer.isPlainText(text) {
                Text(text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(parsedBlocks) { block in
                        blockView(block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: text) { _, newValue in
            scheduleParse(newValue)
        }
        .onDisappear {
            pendingParse?.cancel()
            pendingParse = nil
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level, value):
            inlineText(value)
                .font(headingFont(level))
                .foregroundStyle(DesignToken.ink)
                .padding(.top, level == 1 ? 4 : 2)
        case let .quote(value):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DesignToken.blue.opacity(0.42))
                    .frame(width: 4)
                inlineText(value)
                    .font(.body)
                    .foregroundStyle(DesignToken.muted)
                    .lineSpacing(4)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 10)
            .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .divider:
            Rectangle()
                .fill(DesignToken.border)
                .frame(height: 1)
                .padding(.vertical, 6)
        case let .paragraph(value):
            inlineText(value)
                .font(.body)
                .lineSpacing(4)
        case let .list(items, ordered):
            MarkdownListView(items: items, ordered: ordered)
        case let .code(language, value, isComplete):
            CodeBlockView(language: language, code: value, isComplete: isComplete)
        case let .table(rows):
            MarkdownTableView(rows: rows)
        }
    }

    private func inlineText(_ value: String) -> Text {
        MarkdownInlineRenderer.text(value)
    }

    private func scheduleParse(_ newValue: String) {
        let renderable = isStreaming ? MarkdownStreamingBuffer.renderablePrefix(newValue) : newValue
        guard renderable != parsedText else { return }

        if isStreaming {
            pendingParse?.cancel()
            let work = DispatchWorkItem {
                parsedText = renderable
                parsedBlocks = MarkdownBlock.parse(renderable)
            }
            pendingParse = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        } else {
            parsedText = renderable
            parsedBlocks = MarkdownBlock.parse(renderable)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline.bold()
        case 4: .subheadline.bold()
        case 5: .caption.bold()
        default: .caption2.bold()
        }
    }

}

struct MarkdownListItem: Hashable {
    var marker: String
    var text: String
    var children: [MarkdownListBlock] = []
}

struct MarkdownListBlock: Hashable {
    var ordered: Bool
    var items: [MarkdownListItem]
}

struct MarkdownListView: View {
    let items: [MarkdownListItem]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? orderedMarker(for: item, fallback: index + 1) : "•")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignToken.blue)
                            .frame(width: ordered ? 34 : 14, alignment: .trailing)
                        MarkdownInlineRenderer.text(item.text)
                            .font(.body)
                            .lineSpacing(3)
                    }
                    ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                        MarkdownListView(items: child.items, ordered: child.ordered)
                            .padding(.leading, ordered ? 34 : 22)
                    }
                }
            }
        }
    }

    private func orderedMarker(for item: MarkdownListItem, fallback: Int) -> String {
        item.marker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(fallback)." : item.marker
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    let isComplete: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.lowercase)
                        .padding(.leading, 12)
                        .padding(.top, 8)
                }
                if !isComplete {
                    Text("正在接收代码…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DesignToken.orange)
                        .padding(.top, 8)
                }
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(copied ? DesignToken.mint : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.6), in: Capsule())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 8)
                .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(CodeHighlighter.highlight(code, language: language))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignToken.border.opacity(0.5)))
    }
}

struct MarkdownTableView: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inlineMarkdown: cell)
                                .font(rowIndex == 0 ? .caption.weight(.bold) : .caption)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(minWidth: 90, maxWidth: 220, alignment: .leading)
                                .background(rowIndex == 0 ? Color.blue.opacity(0.09) : Color.white.opacity(rowIndex.isMultiple(of: 2) ? 0.58 : 0.34))
                                .border(DesignToken.border.opacity(0.8), width: 0.5)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
    }
}

extension Text {
    init(inlineMarkdown value: String) {
        if let attributed = try? AttributedString(markdown: value, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            self.init(attributed)
        } else {
            self.init(value)
        }
    }
}

struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case quote(String)
        case divider
        case paragraph(String)
        case list([MarkdownListItem], Bool)
        case code(String?, String, Bool)
        case table([[String]])

        var cacheKey: String {
            switch self {
            case let .heading(level, value):
                return "heading-\(level)-\(value.hashValue)"
            case let .quote(value):
                return "quote-\(value.hashValue)"
            case .divider:
                return "divider"
            case let .paragraph(value):
                return "paragraph-\(value.hashValue)"
            case let .list(items, ordered):
                return "list-\(ordered)-\(items.hashValue)"
            case let .code(language, value, isComplete):
                return "code-\(language ?? "")-\(isComplete)-\(value.hashValue)"
            case let .table(rows):
                return "table-\(rows.hashValue)"
            }
        }
    }

    let id: String
    let kind: Kind

    init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        func append(_ kind: Kind) {
            blocks.append(MarkdownBlock(id: "\(blocks.count)-\(kind.cacheKey)", kind: kind))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = fenceLanguage(from: trimmed)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                let isComplete = index < lines.count
                if isComplete { index += 1 }
                if isComplete || !codeLines.isEmpty || language != nil {
                    append(.code(language, codeLines.joined(separator: "\n"), isComplete))
                } else {
                    append(.paragraph(line))
                }
                continue
            }

            if let heading = parseHeading(trimmed) {
                append(.heading(heading.level, heading.text))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") || current.isEmpty else { break }
                    if current.isEmpty {
                        // Empty line between quote blocks — check if next line continues the quote
                        if index + 1 < lines.count, lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                            index += 1
                            continue
                        } else {
                            break
                        }
                    }
                    var value = String(current.dropFirst())
                    if value.hasPrefix(" ") { value = String(value.dropFirst()) }
                    if value.hasPrefix(">") { value = String(value.dropFirst()).trimmingCharacters(in: .init(charactersIn: " ")) }
                    if value.isEmpty {
                        quoteLines.append("")
                    } else {
                        quoteLines.append(value)
                    }
                    index += 1
                }
                // Join lines, collapsing multiple empty lines into one
                let joined = quoteLines.joined(separator: " ").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                append(.quote(joined))
                continue
            }

            if isTableStart(lines, at: index) {
                var tableLines: [String] = []
                while index < lines.count, lines[index].contains("|") {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if !isTableSeparator(current) { tableLines.append(current) }
                    index += 1
                }
                append(.table(tableLines.map(tableCells)))
                continue
            }

            if let list = parseList(lines, start: index) {
                append(.list(list.block.items, list.block.ordered))
                index = list.nextIndex
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("```") || next.hasPrefix(">") || isDivider(next) || parseHeading(next) != nil || isTableStart(lines, at: index) || parseList(lines, start: index) != nil { break }
                paragraphLines.append(next)
                index += 1
            }
            append(.paragraph(paragraphLines.joined(separator: "\n")))
        }

        return blocks.isEmpty ? [MarkdownBlock(id: "0-empty", kind: .paragraph(text))] : blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func fenceLanguage(from line: String) -> String? {
        let value = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private static func isDivider(_ line: String) -> Bool {
        line.range(of: #"^\s*(-\s*){3,}$"#, options: .regularExpression) != nil
    }

    private static func parseList(_ lines: [String], start: Int) -> (block: MarkdownListBlock, nextIndex: Int)? {
        guard start < lines.count else { return nil }
        guard let firstMarker = parseListMarker(lines[start]) else { return nil }
        return parseListBlock(lines, start: start, baseIndent: firstMarker.indent, ordered: firstMarker.ordered)
    }

    private static func parseListBlock(_ lines: [String], start: Int, baseIndent: Int, ordered: Bool) -> (block: MarkdownListBlock, nextIndex: Int)? {
        var items: [MarkdownListItem] = []
        var index = start

        while index < lines.count {
            guard let marker = parseListMarker(lines[index]), marker.indent == baseIndent, marker.ordered == ordered else { break }
            var item = MarkdownListItem(marker: marker.marker, text: marker.text)
            index += 1

            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                    continue
                }
                guard let nextMarker = parseListMarker(lines[index]) else { break }
                if nextMarker.indent <= baseIndent { break }
                guard let child = parseListBlock(lines, start: index, baseIndent: nextMarker.indent, ordered: nextMarker.ordered) else { break }
                item.children.append(child.block)
                index = child.nextIndex
            }

            items.append(item)
        }

        guard !items.isEmpty else { return nil }
        return (MarkdownListBlock(ordered: ordered, items: items), index)
    }

    private static func parseListMarker(_ line: String) -> (indent: Int, ordered: Bool, marker: String, text: String)? {
        guard let match = line.firstMatch(of: /^(\s*)((\d+)\.|[-*])\s+(.*)$/) else { return nil }
        let marker = String(match.2)
        return (
            indent: String(match.1).count,
            ordered: marker.hasSuffix("."),
            marker: marker,
            text: String(match.4)
        )
    }

    private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return lines[index].contains("|") && isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.range(of: #"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#, options: .regularExpression) != nil
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

enum MarkdownInlineRenderer {
    private static let markdownScalars = CharacterSet(charactersIn: "*_`[<\\")

    static func isPlainText(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        if value.rangeOfCharacter(from: markdownScalars) != nil { return false }
        if value.range(of: #"(?m)^\s*(#{1,6}\s|[-*]\s|\d+\.\s|>|---+\s*$|\|.*\|)"#, options: .regularExpression) != nil { return false }
        return true
    }

    static func text(_ value: String) -> Text {
        if isPlainText(value) {
            return Text(value)
        }
        if let attributed = try? AttributedString(markdown: value, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(value)
    }
}

enum CodeHighlighter {
    private static let keywordColor = Color(red: 0.52, green: 0.22, blue: 0.72)
    private static let stringColor = Color(red: 0.08, green: 0.48, blue: 0.24)
    private static let commentColor = Color(red: 0.42, green: 0.48, blue: 0.56)
    private static let numberColor = Color(red: 0.10, green: 0.34, blue: 0.72)

    private static let keywordsByLanguage: [String: Set<String>] = [
        "swift": ["actor", "any", "as", "async", "await", "break", "case", "catch", "class", "continue", "defer", "do", "else", "enum", "extension", "false", "for", "func", "guard", "if", "import", "in", "init", "is", "let", "nil", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throw", "throws", "true", "try", "var", "where", "while"],
        "javascript": ["await", "break", "case", "catch", "class", "const", "continue", "default", "else", "export", "false", "finally", "for", "from", "function", "if", "import", "let", "new", "null", "return", "switch", "this", "throw", "true", "try", "undefined", "var", "while", "yield"],
        "typescript": ["await", "break", "case", "catch", "class", "const", "continue", "default", "else", "enum", "export", "false", "finally", "for", "from", "function", "if", "implements", "import", "interface", "let", "new", "null", "private", "protected", "public", "readonly", "return", "switch", "this", "throw", "true", "try", "type", "undefined", "var", "while", "yield"],
        "python": ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "elif", "else", "except", "False", "finally", "for", "from", "if", "import", "in", "is", "lambda", "None", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"],
        "json": ["true", "false", "null"],
        "bash": ["case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "then", "while"],
        "shell": ["case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "then", "while"]
    ]

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = DesignToken.ink
        guard !code.isEmpty else { return attributed }

        let normalizedLanguage = normalized(language)
        colorMatches(in: code, attributed: &attributed, pattern: #"//.*|#.*|/\*[\s\S]*?\*/"#, color: commentColor)
        colorMatches(in: code, attributed: &attributed, pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, color: stringColor)
        colorMatches(in: code, attributed: &attributed, pattern: #"\b\d+(?:\.\d+)?\b"#, color: numberColor)

        let keywords = keywordsByLanguage[normalizedLanguage] ?? keywordsByLanguage["swift"] ?? []
        if !keywords.isEmpty {
            let escaped = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            colorMatches(in: code, attributed: &attributed, pattern: #"\b("# + escaped + #")\b"#, color: keywordColor, weight: .semibold)
        }

        return attributed
    }

    private static func normalized(_ language: String?) -> String {
        switch language?.lowercased() {
        case "js", "jsx": "javascript"
        case "ts", "tsx": "typescript"
        case "py": "python"
        case "sh", "zsh", "shellscript": "shell"
        default: language?.lowercased() ?? ""
        }
    }

    private static func colorMatches(in source: String, attributed: inout AttributedString, pattern: String, color: Color, weight: Font.Weight? = nil) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: nsRange) {
            guard let range = Range(match.range, in: source), let attributedRange = Range(range, in: attributed) else { continue }
            attributed[attributedRange].foregroundColor = color
            if let weight {
                attributed[attributedRange].font = .system(.callout, design: .monospaced).weight(weight)
            }
        }
    }
}

enum MarkdownStreamingBuffer {
    private static let maxBufferedCharacters = 1_200

    static func renderablePrefix(_ markdown: String) -> String {
        guard markdown.count > maxBufferedCharacters else { return markdown }

        var inFence = false
        var lastBoundary: String.Index?
        var index = markdown.startIndex
        var lineStart = markdown.startIndex

        while index < markdown.endIndex {
            if markdown[index] == "\n" {
                let line = String(markdown[lineStart..<index]).trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("```") {
                    inFence.toggle()
                }
                let next = markdown.index(after: index)
                if !inFence, next < markdown.endIndex, markdown[next] == "\n" {
                    lastBoundary = markdown.index(after: next)
                }
                lineStart = next
            }
            index = markdown.index(after: index)
        }

        guard let boundary = lastBoundary else { return markdown }
        let bufferedLength = markdown.distance(from: boundary, to: markdown.endIndex)
        return bufferedLength > maxBufferedCharacters ? markdown : String(markdown[..<boundary])
    }
}

