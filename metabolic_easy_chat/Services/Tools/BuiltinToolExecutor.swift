//
//  BuiltinToolExecutor.swift
//  metabolic_easy_chat
//
//  Created by GitHub Copilot on 2026/5/19.
//

import Foundation
import JavaScriptCore

struct BuiltinToolRequest: Decodable {
    let tool: String
    let cmd: String?
    let url: String?
    let urls: [String]?
    let query: String?
    let code: String?
    let command: String?
    let args: [String]?
    let timeout: Int?
    let skill: String?
    let files: [String]?
    let path: String?
    let content: String?
    let append: Bool?
    let maxDepth: Int?
    let pattern: String?
    let glob: String?
    let replacement: String?
    let oldString: String?
    let newString: String?
    let line: Int?
    let limit: Int?
    let offset: Int?
    let since: String?
    let language: String?

    enum CodingKeys: String, CodingKey {
        case tool
        case cmd
        case url
        case urls
        case query
        case code
        case command
        case args
        case timeout
        case skill
        case files
        case path
        case content
        case append
        case maxDepth
        case pattern
        case glob
        case replacement
        case oldString
        case newString
        case line
        case limit
        case offset
        case since
        case language
        case maxOutput = "max_output"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cmd = try container.decodeIfPresent(String.self, forKey: .cmd)
        tool = try container.decodeIfPresent(String.self, forKey: .tool) ?? (cmd == nil ? "" : "terminal")
        url = try container.decodeIfPresent(String.self, forKey: .url)
        urls = try container.decodeIfPresent([String].self, forKey: .urls)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? (cmd == nil ? nil : "bash")
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? cmd.map { ["-lc", $0] }
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
        skill = try container.decodeIfPresent(String.self, forKey: .skill)
        files = try container.decodeIfPresent([String].self, forKey: .files)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        append = try container.decodeIfPresent(Bool.self, forKey: .append)
        maxDepth = try container.decodeIfPresent(Int.self, forKey: .maxDepth)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
        glob = try container.decodeIfPresent(String.self, forKey: .glob)
        replacement = try container.decodeIfPresent(String.self, forKey: .replacement)
        oldString = try container.decodeIfPresent(String.self, forKey: .oldString)
        newString = try container.decodeIfPresent(String.self, forKey: .newString)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? container.decodeIfPresent(Int.self, forKey: .maxOutput)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
        since = try container.decodeIfPresent(String.self, forKey: .since)
        language = try container.decodeIfPresent(String.self, forKey: .language)
    }

    static func manual(tool: String, command: String? = nil, args: [String]? = nil, timeout: Int? = nil, skill: String? = nil) -> BuiltinToolRequest {
        BuiltinToolRequest(tool: tool, cmd: nil, url: nil, urls: nil, query: nil, code: nil, command: command, args: args, timeout: timeout, skill: skill, files: nil, path: nil, content: nil, append: nil, maxDepth: nil, pattern: nil, glob: nil, replacement: nil, oldString: nil, newString: nil, line: nil, limit: nil, offset: nil, since: nil, language: nil)
    }

    private init(tool: String, cmd: String?, url: String?, urls: [String]?, query: String?, code: String?, command: String?, args: [String]?, timeout: Int?, skill: String?, files: [String]?, path: String?, content: String?, append: Bool?, maxDepth: Int?, pattern: String?, glob: String?, replacement: String?, oldString: String?, newString: String?, line: Int?, limit: Int?, offset: Int?, since: String?, language: String?) {
        self.tool = tool
        self.cmd = cmd
        self.url = url
        self.urls = urls
        self.query = query
        self.code = code
        self.command = command
        self.args = args
        self.timeout = timeout
        self.skill = skill
        self.files = files
        self.path = path
        self.content = content
        self.append = append
        self.maxDepth = maxDepth
        self.pattern = pattern
        self.glob = glob
        self.replacement = replacement
        self.oldString = oldString
        self.newString = newString
        self.line = line
        self.limit = limit
        self.offset = offset
        self.since = since
        self.language = language
    }
}

struct BuiltinToolResult {
    let title: String
    let output: String
    let status: ToolRunStatus
}

final class BuiltinToolExecutor {
    private let settings: ProviderSettings
    private let session: URLSession

    init(settings: ProviderSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func executeTools(in text: String) async throws -> [BuiltinToolResult] {
        guard settings.enableBuiltinTools else { return [] }
        let requests = extractToolRequests(from: text)
        var results: [BuiltinToolResult] = []
        for request in requests.prefix(5) {
            results.append(await executeSafely(request))
        }
        return results
    }

    func executeSingleRequest(_ request: BuiltinToolRequest) async -> BuiltinToolResult {
        return await executeSafely(request)
    }

    private func executeSafely(_ request: BuiltinToolRequest) async -> BuiltinToolResult {
        do {
            return try await execute(request)
        } catch {
            return BuiltinToolResult(title: title(for: request), output: error.localizedDescription, status: .failed)
        }
    }

    func pendingToolTitles(in text: String) -> [String] {
        guard settings.enableBuiltinTools else { return [] }
        return extractToolRequests(from: text).prefix(5).map(title)
    }

    private func title(for request: BuiltinToolRequest) -> String {
        switch request.tool {
        case "web_search":
            return "web_search: \(request.query ?? "")"
        case "fetch_url":
            return "fetch_url: \(request.url ?? "")"
        case "fetch_urls":
            return "fetch_urls: \(request.urls?.count ?? 0) urls"
        case "url_to_markdown":
            return "url_to_markdown: \(request.url ?? "")"
        case "run_javascript":
            return "run_javascript"
        case "read_file":
            return "read_file: \(request.path ?? "")"
        case "view":
            return "view: \(request.path ?? "")"
        case "write_file":
            return "write_file: \(request.path ?? "")"
        case "create_file", "create":
            return "create_file: \(request.path ?? "")"
        case "create_directory":
            return "create_directory: \(request.path ?? "")"
        case "replace_string", "str_replace":
            return "replace_string: \(request.path ?? "")"
        case "insert":
            return "insert: \(request.path ?? "")"
        case "glob", "file_search":
            return "glob: \(request.pattern ?? request.query ?? "")"
        case "grep", "rg", "grep_search":
            return "grep: \(request.pattern ?? request.query ?? "")"
        case "list_files":
            return "list_files: \(request.path ?? ".")"
        case "list_dir", "LS":
            return "list_dir: \(request.path ?? ".")"
        case "read_project_structure":
            return "read_project_structure: \(request.path ?? ".")"
        case "get_errors":
            return "get_errors"
        case "think":
            return "think"
        case "report_progress":
            return "report_progress"
        case "task_complete":
            return "task_complete"
        case "terminal":
            return "terminal: \(request.command ?? "")"
        case "terminal_read":
            return "terminal_read"
        case "extract_links":
            return "extract_links: \(request.url ?? "")"
        case "github_trending":
            return "github_trending: \(request.language ?? "all") / \(request.since ?? "daily")"
        default:
            return request.tool
        }
    }

    private func execute(_ request: BuiltinToolRequest) async throws -> BuiltinToolResult {
        switch request.tool {
        case "web_search":
            guard let query = request.query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ChatError.builtinToolFailed("web_search 缺少 query。")
            }
            let content = try await webSearch(query)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "fetch_url":
            guard let urlString = request.url else {
                throw ChatError.builtinToolFailed("fetch_url 缺少 url。")
            }
            let content = try await fetchURL(urlString)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "fetch_urls":
            guard let urls = request.urls, !urls.isEmpty else {
                throw ChatError.builtinToolFailed("fetch_urls 缺少 urls。")
            }
            let content = await fetchURLs(urls)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "url_to_markdown":
            guard let urlString = request.url else {
                throw ChatError.builtinToolFailed("url_to_markdown 缺少 url。")
            }
            let content = try await urlToMarkdown(urlString)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "run_javascript":
            guard let code = request.code else {
                throw ChatError.builtinToolFailed("run_javascript 缺少 code。")
            }
            let content = try runJavaScript(code)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "read_file":
            guard let path = request.path else {
                throw ChatError.builtinToolFailed("read_file 缺少 path。")
            }
            let content = try readLocalFile(path)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "view":
            guard let path = request.path else {
                throw ChatError.builtinToolFailed("view 缺少 path。")
            }
            let content = try readLocalFile(path, offset: request.offset, limit: request.limit)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "write_file":
            guard let path = request.path, let content = request.content else {
                throw ChatError.builtinToolFailed("write_file 缺少 path 或 content。")
            }
            let output = try writeLocalFile(path: path, content: content, append: request.append ?? false)
            return BuiltinToolResult(title: title(for: request), output: output, status: .completed)
        case "create_file", "create":
            guard let path = request.path, let content = request.content else {
                throw ChatError.builtinToolFailed("create_file 缺少 path 或 content。")
            }
            let output = try createLocalFile(path: path, content: content)
            return BuiltinToolResult(title: title(for: request), output: output, status: .completed)
        case "create_directory":
            guard let path = request.path else {
                throw ChatError.builtinToolFailed("create_directory 缺少 path。")
            }
            let output = try createDirectory(path: path)
            return BuiltinToolResult(title: title(for: request), output: output, status: .completed)
        case "replace_string", "str_replace":
            guard let path = request.path, let oldString = request.oldString ?? request.pattern, let newString = request.newString ?? request.replacement else {
                throw ChatError.builtinToolFailed("replace_string 缺少 path、oldString/pattern 或 newString/replacement。")
            }
            let output = try replaceString(path: path, oldString: oldString, newString: newString)
            return BuiltinToolResult(title: title(for: request), output: output, status: .completed)
        case "insert":
            guard let path = request.path, let content = request.content, let line = request.line else {
                throw ChatError.builtinToolFailed("insert 缺少 path、line 或 content。")
            }
            let output = try insertText(path: path, line: line, content: content)
            return BuiltinToolResult(title: title(for: request), output: output, status: .completed)
        case "list_files":
            let content = try listFiles(path: request.path, maxDepth: request.maxDepth ?? 2)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "list_dir", "LS":
            let content = try listFiles(path: request.path, maxDepth: 1)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "read_project_structure":
            let content = try listFiles(path: request.path, maxDepth: request.maxDepth ?? 4)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "glob", "file_search":
            let content = try globFiles(pattern: request.pattern ?? request.query ?? "*", path: request.path, limit: request.limit ?? 200)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "grep", "rg", "grep_search":
            let content = try grepFiles(pattern: request.pattern ?? request.query ?? "", path: request.path, glob: request.glob, limit: request.limit ?? 80)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "extract_links":
            guard let urlString = request.url else {
                throw ChatError.builtinToolFailed("extract_links 缺少 url。")
            }
            let content = try await extractLinks(urlString)
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        case "get_errors":
            return BuiltinToolResult(title: title(for: request), output: "当前轻量版无法读取 Xcode/VS Code Problems 面板。建议使用 terminal 运行 swift/xcodebuild 获取诊断。", status: .completed)
        case "think":
            return BuiltinToolResult(title: title(for: request), output: request.query ?? request.content ?? "已记录思考。", status: .completed)
        case "report_progress":
            return BuiltinToolResult(title: title(for: request), output: request.query ?? request.content ?? "已记录进度。", status: .completed)
        case "task_complete":
            return BuiltinToolResult(title: title(for: request), output: request.query ?? request.content ?? "任务完成。", status: .completed)
        case "github_trending":
            let content = try await fetchGitHubTrending(language: request.language, since: request.since ?? "daily")
            return BuiltinToolResult(title: title(for: request), output: content, status: .completed)
        default:
            throw ChatError.builtinToolFailed("未知工具：\(request.tool)")
        }
    }

    private func extractToolRequests(from text: String) -> [BuiltinToolRequest] {
        extractJSONObjects(from: text).compactMap { jsonText in
            guard let data = jsonText.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(BuiltinToolRequest.self, from: data)
        }
    }

    private func extractJSONObjects(from text: String) -> [String] {
        // Remove content inside code blocks before parsing
        let cleaned = removeCodeBlocks(from: text)

        var objects: [String] = []
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in cleaned.indices {
            let character = cleaned[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                if depth == 0 { startIndex = index }
                depth += 1
            } else if character == "}" {
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let objectStart = startIndex {
                    let object = String(cleaned[objectStart...index])
                    if object.contains("\"tool\"") || object.contains("\"cmd\"") { objects.append(object) }
                    startIndex = nil
                }
            }
        }
        return objects
    }

    private func removeCodeBlocks(from text: String) -> String {
        var result = text
        // Remove fenced code blocks (```...```)
        while let startRange = result.range(of: "```") {
            if let endRange = result.range(of: "```", range: startRange.upperBound..<result.endIndex) {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                result.removeSubrange(startRange.lowerBound..<result.endIndex)
            }
        }
        // Remove inline code (`...`)
        while let startRange = result.range(of: "`") {
            if let endRange = result.range(of: "`", range: startRange.upperBound..<result.endIndex) {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                break
            }
        }
        return result
    }

    private func fetchGitHubTrending(language: String?, since: String) async throws -> String {
        var path = "https://github.com/trending"
        if let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            path += "/" + language.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalizedSince = ["daily", "weekly", "monthly"].contains(since) ? since : "daily"
        return try await fetchURL("\(path)?since=\(normalizedSince)")
    }

    private func webSearch(_ query: String) async throws -> String {
        var components = URLComponents(string: "https://duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let urlString = components?.url?.absoluteString else {
            throw ChatError.builtinToolFailed("搜索关键词无效。")
        }
        let html = try await fetchRawHTML(urlString)
        let pattern = #"<a[^>]*class=\"[^"]*result__a[^"]*\"[^>]*href=\"([^"]+)\"[^>]*>([\s\S]*?)</a>[\s\S]*?<a[^>]*class=\"[^"]*result__snippet[^"]*\"[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return htmlToReadableText(html) }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)).prefix(8)
        let lines = matches.enumerated().compactMap { index, match -> String? in
            guard let hrefRange = Range(match.range(at: 1), in: html), let titleRange = Range(match.range(at: 2), in: html), let snippetRange = Range(match.range(at: 3), in: html) else { return nil }
            let href = normalizeDuckDuckGoURL(String(html[hrefRange]))
            let title = htmlToReadableText(String(html[titleRange]))
            let snippet = htmlToReadableText(String(html[snippetRange]))
            return "\(index + 1). \(title)\n链接：\(href)\n摘要：\(snippet)"
        }
        return lines.isEmpty ? String(htmlToReadableText(html).prefix(8_000)) : lines.joined(separator: "\n\n")
    }

    private func fetchURLs(_ urls: [String]) async -> String {
        var sections: [String] = []
        for url in urls.prefix(5) {
            do {
                let content = try await fetchURL(url)
                sections.append("URL：\(url)\n状态：成功\n内容：\n\(content)")
            } catch {
                sections.append("URL：\(url)\n状态：失败\n错误：\(error.localizedDescription)")
            }
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    private func urlToMarkdown(_ urlString: String) async throws -> String {
        let html = try await fetchRawHTML(urlString)
        var markdown = html
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<h1[^>]*>([\s\S]*?)</h1>"#, with: "\n# $1\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<h2[^>]*>([\s\S]*?)</h2>"#, with: "\n## $1\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<h3[^>]*>([\s\S]*?)</h3>"#, with: "\n### $1\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<li[^>]*>([\s\S]*?)</li>"#, with: "\n- $1", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<p[^>]*>([\s\S]*?)</p>"#, with: "\n$1\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<a[^>]*href=\"([^\"]+)\"[^>]*>([\s\S]*?)</a>"#, with: "[$2]($1)", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        markdown = decodeHTMLEntities(markdown).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(markdown.prefix(18_000))
    }

    private func runJavaScript(_ code: String) throws -> String {
        guard code.count <= 8_000 else { throw ChatError.builtinToolFailed("JavaScript 代码过长。") }
        guard !code.localizedCaseInsensitiveContains("while(true)") else { throw ChatError.builtinToolFailed("拒绝执行无限循环代码。") }
        let context = JSContext()
        var logs: [String] = []
        let consoleLog: @convention(block) (String) -> Void = { logs.append($0) }
        context?.setObject(["log": consoleLog], forKeyedSubscript: "console" as NSString)
        context?.exceptionHandler = { _, exception in logs.append("Exception: \(exception?.toString() ?? "未知错误")") }
        let result = context?.evaluateScript(code)?.toString()
        let output = (logs + [result].compactMap { $0 }).joined(separator: "\n")
        return output.isEmpty ? "执行完成，无输出。" : String(output.prefix(12_000))
    }

    private func readLocalFile(_ path: String, offset: Int? = nil, limit: Int? = nil) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { throw ChatError.builtinToolFailed("文件不存在：\(path)") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 2_000_000 else { throw ChatError.builtinToolFailed("文件过大，请选择 2MB 以内文本文件。") }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ChatError.builtinToolFailed("无法按文本读取文件。")
        }
        if let offset {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let start = max(offset - 1, 0)
            guard start < lines.count else { return "" }
            let end = min(start + max(limit ?? 200, 1), lines.count)
            return lines[start..<end].enumerated().map { index, line in "\(start + index + 1): \(line)" }.joined(separator: "\n")
        }
        return String(text.prefix(20_000))
    }

    private func createLocalFile(path: String, content: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { throw ChatError.builtinToolFailed("文件已存在：\(path)") }
        return try writeLocalFile(path: path, content: content, append: false)
    }

    private func writeLocalFile(path: String, content: String, append: Bool) throws -> String {
        guard content.count <= 500_000 else { throw ChatError.builtinToolFailed("写入内容过大，请控制在 500KB 以内。") }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard let data = content.data(using: .utf8) else { throw ChatError.builtinToolFailed("写入内容无法编码为 UTF-8。") }
        if append, FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: .atomic)
        }
        return "已\(append ? "追加" : "写入") \(data.count) bytes：\(url.path)"
    }

    private func createDirectory(path: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return "已创建目录：\(url.path)"
    }

    private func replaceString(path: String, oldString: String, newString: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let original = try readLocalFile(path)
        let count = original.components(separatedBy: oldString).count - 1
        guard count > 0 else { throw ChatError.builtinToolFailed("未找到要替换的文本。") }
        guard count == 1 else { throw ChatError.builtinToolFailed("找到 \(count) 处匹配，请提供更精确的 oldString。") }
        let updated = original.replacingOccurrences(of: oldString, with: newString)
        try updated.data(using: .utf8)?.write(to: url, options: .atomic)
        return "已替换 1 处：\(url.path)"
    }

    private func insertText(path: String, line: Int, content: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let original = try readLocalFile(path)
        var lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let index = min(max(line, 0), lines.count)
        lines.insert(contentsOf: content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init), at: index)
        let updated = lines.joined(separator: "\n")
        try updated.data(using: .utf8)?.write(to: url, options: .atomic)
        return "已在第 \(line) 行插入文本：\(url.path)"
    }

    private func listFiles(path: String?, maxDepth: Int) throws -> String {
        let rootPath = path?.isEmpty == false ? path! : FileManager.default.currentDirectoryPath
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL
        var output: [String] = [root.path]
        try listFiles(at: root, depth: 0, maxDepth: min(max(maxDepth, 0), 4), output: &output)
        return output.prefix(500).joined(separator: "\n")
    }

    private func listFiles(at url: URL, depth: Int, maxDepth: Int, output: inout [String]) throws {
        guard depth <= maxDepth else { return }
        let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).prefix(80)
        for item in items {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            output.append("\(String(repeating: "  ", count: depth))- \(item.lastPathComponent)\(isDirectory ? "/" : "")")
            if isDirectory { try listFiles(at: item, depth: depth + 1, maxDepth: maxDepth, output: &output) }
        }
    }

    private func globFiles(pattern: String, path: String?, limit: Int) throws -> String {
        let root = URL(fileURLWithPath: path?.isEmpty == false ? path! : FileManager.default.currentDirectoryPath).standardizedFileURL
        let regex = try globRegex(pattern)
        var matches: [String] = []
        try enumerateFiles(root: root, maxDepth: 8) { fileURL, isDirectory in
            guard !isDirectory else { return }
            let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            if regex.firstMatch(in: relative, range: NSRange(relative.startIndex..<relative.endIndex, in: relative)) != nil {
                matches.append(relative)
            }
        }
        return matches.prefix(max(limit, 1)).joined(separator: "\n").isEmpty ? "未找到匹配文件。" : matches.prefix(max(limit, 1)).joined(separator: "\n")
    }

    private func grepFiles(pattern: String, path: String?, glob: String?, limit: Int) throws -> String {
        guard !pattern.isEmpty else { throw ChatError.builtinToolFailed("grep 缺少 pattern。") }
        let root = URL(fileURLWithPath: path?.isEmpty == false ? path! : FileManager.default.currentDirectoryPath).standardizedFileURL
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let globMatcher = try glob.map(globRegex)
        var output: [String] = []
        try enumerateFiles(root: root, maxDepth: 8) { fileURL, isDirectory in
            guard output.count < max(limit, 1), !isDirectory else { return }
            let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            if let globMatcher, globMatcher.firstMatch(in: relative, range: NSRange(relative.startIndex..<relative.endIndex, in: relative)) == nil { return }
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe), data.count <= 1_000_000, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let lineText = String(line)
                if regex.firstMatch(in: lineText, range: NSRange(lineText.startIndex..<lineText.endIndex, in: lineText)) != nil {
                    output.append("\(relative):\(index + 1): \(lineText)")
                    if output.count >= max(limit, 1) { return }
                }
            }
        }
        return output.isEmpty ? "未找到匹配内容。" : output.joined(separator: "\n")
    }

    private func enumerateFiles(root: URL, maxDepth: Int, visit: (URL, Bool) throws -> Void) throws {
        func walk(_ directory: URL, depth: Int) throws {
            guard depth <= maxDepth else { return }
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .filter { ![".git", "node_modules", "DerivedData", ".build"].contains($0.lastPathComponent) }
            for child in children {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                try visit(child, isDirectory)
                if isDirectory { try walk(child, depth: depth + 1) }
            }
        }
        try walk(root, depth: 0)
    }

    private func globRegex(_ pattern: String) throws -> NSRegularExpression {
        var regex = NSRegularExpression.escapedPattern(for: pattern)
        regex = regex.replacingOccurrences(of: #"\*\*"#, with: #".*"#)
        regex = regex.replacingOccurrences(of: #"\*"#, with: #"[^/]*"#)
        regex = regex.replacingOccurrences(of: #"\?"#, with: #"."#)
        return try NSRegularExpression(pattern: "^\(regex)$", options: [.caseInsensitive])
    }

    private func extractLinks(_ urlString: String) async throws -> String {
        let html = try await fetchRawHTML(urlString)
        guard let baseURL = URL(string: urlString), let regex = try? NSRegularExpression(pattern: #"<a[^>]+href=\"([^\"]+)\"[^>]*>([\s\S]*?)</a>"#, options: [.caseInsensitive]) else {
            throw ChatError.builtinToolFailed("无法解析链接。")
        }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)).prefix(80)
        var seen = Set<String>()
        let links = matches.compactMap { match -> String? in
            guard let hrefRange = Range(match.range(at: 1), in: html), let titleRange = Range(match.range(at: 2), in: html) else { return nil }
            let rawHref = decodeHTMLEntities(String(html[hrefRange]))
            guard let absolute = URL(string: rawHref, relativeTo: baseURL)?.absoluteURL, ["http", "https"].contains(absolute.scheme?.lowercased()) else { return nil }
            guard seen.insert(absolute.absoluteString).inserted else { return nil }
            let label = htmlToReadableText(String(html[titleRange]))
            return "- \(label.isEmpty ? absolute.absoluteString : label)\n  \(absolute.absoluteString)"
        }
        return links.isEmpty ? "未提取到链接。" : links.joined(separator: "\n")
    }

    private func fetchURL(_ urlString: String) async throws -> String {
        let raw = try await fetchRawHTML(urlString)
        let readable = htmlToReadableText(raw)
        return String(readable.prefix(16_000))
    }

    private func fetchRawHTML(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw ChatError.builtinToolFailed("URL 无效：\(urlString)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(max(3, settings.builtinToolTimeout))
        request.setValue("Mozilla/5.0 EasyChat/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ChatError.builtinToolFailed("HTTP \(http.statusCode)：\(urlString)")
        }

        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return raw
    }

    private func normalizeDuckDuckGoURL(_ raw: String) -> String {
        let decoded = decodeHTMLEntities(raw)
        guard let components = URLComponents(string: decoded), components.path == "/l/" else { return decoded }
        return components.queryItems?.first(where: { $0.name == "uddg" })?.value ?? decoded
    }

    private func htmlToReadableText(_ html: String) -> String {
        var text = decodeHTMLEntities(html)
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? html : text
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
