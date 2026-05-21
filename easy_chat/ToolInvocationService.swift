//
//  ToolInvocationService.swift
//  easy_chat
//
//  Created by GitHub Copilot on 2026/5/20.
//

import Foundation

struct ToolDefinition: Identifiable, Hashable {
    enum Category: String, Codable, Hashable {
        case readOnly
        case edit
        case execution
        case mcp
        case interaction
        case web
    }

    var id: String { name }
    var name: String
    var displayName: String
    var description: String
    var category: Category
    var requiresConfirmation: Bool
    var inputSchemaHint: String
}

struct ToolInvocation: Identifiable {
    var id: String
    var name: String
    var input: BuiltinToolRequest
    var rawJSON: String
}

struct ToolInvocationRecord: Identifiable, Codable, Hashable {
    var id: String
    var toolName: String
    var displayName: String
    var input: String
    var output: String
    var status: ToolRunStatus
    var isConfirmed: Bool?
    var isComplete: Bool
    var createdAt = Date()

    var title: String { displayName }
}

struct ToolPermissionDecision {
    enum Behavior {
        case allow
        case deny
        case ask
    }

    var behavior: Behavior
    var reason: String?
}

final class ToolInvocationService {
    private let settings: ProviderSettings

    init(settings: ProviderSettings) {
        self.settings = settings
    }

    var definitions: [ToolDefinition] {
        var tools: [ToolDefinition] = [
            ToolDefinition(name: "web_search", displayName: "Web Search", description: "搜索网页并返回摘要。", category: .web, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"web_search\",\"query\":\"关键词\"}"),
            ToolDefinition(name: "fetch_url", displayName: "Fetch URL", description: "抓取网页可读文本。", category: .web, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"fetch_url\",\"url\":\"https://example.com\"}"),
            ToolDefinition(name: "fetch_urls", displayName: "Fetch URLs", description: "批量抓取网页。", category: .web, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"fetch_urls\",\"urls\":[\"https://example.com\"]}"),
            ToolDefinition(name: "url_to_markdown", displayName: "URL to Markdown", description: "把网页转换成 Markdown 风格文本。", category: .web, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"url_to_markdown\",\"url\":\"https://example.com\"}"),
            ToolDefinition(name: "extract_links", displayName: "Extract Links", description: "提取网页链接。", category: .web, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"extract_links\",\"url\":\"https://example.com\"}"),
            ToolDefinition(name: "github_trending", displayName: "GitHub Trending", description: "读取 GitHub Trending。", category: .web, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"github_trending\",\"language\":\"swift\",\"since\":\"daily\"}"),
            ToolDefinition(name: "run_javascript", displayName: "Run JavaScript", description: "执行短 JavaScript 片段。", category: .execution, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"run_javascript\",\"code\":\"1+1\"}"),
            ToolDefinition(name: "read_file", displayName: "Read File", description: "读取本地文本文件。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"read_file\",\"path\":\"/path/file.txt\"}"),
            ToolDefinition(name: "view", displayName: "View File", description: "按行读取文件，支持 offset/limit。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"view\",\"path\":\"/path/file.txt\",\"offset\":1,\"limit\":120}"),
            ToolDefinition(name: "list_files", displayName: "List Files", description: "列出目录文件。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"list_files\",\"path\":\"/path\",\"maxDepth\":2}"),
            ToolDefinition(name: "list_dir", displayName: "List Directory", description: "列出一层目录内容，类似 VS Code list_dir/LS。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"list_dir\",\"path\":\"/path\"}"),
            ToolDefinition(name: "read_project_structure", displayName: "Read Project Structure", description: "读取项目目录结构。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"read_project_structure\",\"path\":\"/path\",\"maxDepth\":4}"),
            ToolDefinition(name: "glob", displayName: "Glob", description: "按 glob 查找文件。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"glob\",\"pattern\":\"**/*.swift\",\"path\":\"/workspace\"}"),
            ToolDefinition(name: "grep", displayName: "Grep", description: "用正则搜索文件内容。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"grep\",\"pattern\":\"TODO|FIXME\",\"path\":\"/workspace\",\"glob\":\"**/*.swift\"}"),
            ToolDefinition(name: "write_file", displayName: "Write File", description: "写入或追加本地文本文件。", category: .edit, requiresConfirmation: true, inputSchemaHint: "{\"tool\":\"write_file\",\"path\":\"/path/file.txt\",\"content\":\"文本\",\"append\":false}"),
            ToolDefinition(name: "create_file", displayName: "Create File", description: "创建新文件，已存在则失败。", category: .edit, requiresConfirmation: true, inputSchemaHint: "{\"tool\":\"create_file\",\"path\":\"/path/file.txt\",\"content\":\"文本\"}"),
            ToolDefinition(name: "create_directory", displayName: "Create Directory", description: "创建目录。", category: .edit, requiresConfirmation: true, inputSchemaHint: "{\"tool\":\"create_directory\",\"path\":\"/path/dir\"}"),
            ToolDefinition(name: "replace_string", displayName: "Replace String", description: "在文件中精确替换唯一字符串。", category: .edit, requiresConfirmation: true, inputSchemaHint: "{\"tool\":\"replace_string\",\"path\":\"/path/file.txt\",\"oldString\":\"旧文本\",\"newString\":\"新文本\"}"),
            ToolDefinition(name: "insert", displayName: "Insert Text", description: "在指定 0-based 行号前插入文本。", category: .edit, requiresConfirmation: true, inputSchemaHint: "{\"tool\":\"insert\",\"path\":\"/path/file.txt\",\"line\":0,\"content\":\"文本\"}"),
            ToolDefinition(name: "terminal", displayName: "Terminal", description: "在当前工作区执行命令。", category: .execution, requiresConfirmation: true, inputSchemaHint: "{\"tool\":\"terminal\",\"command\":\"ls\",\"args\":[\"-la\"],\"timeout\":60}"),
            ToolDefinition(name: "terminal_read", displayName: "Read Terminal", description: "读取当前终端 transcript。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"terminal_read\"}"),
            ToolDefinition(name: "get_errors", displayName: "Get Errors", description: "获取诊断提示；轻量版会提示用终端获取。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"get_errors\"}"),
            ToolDefinition(name: "think", displayName: "Think", description: "记录中间思考或计划，不改变环境。", category: .interaction, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"think\",\"content\":\"计划...\"}"),
            ToolDefinition(name: "report_progress", displayName: "Report Progress", description: "报告当前进度。", category: .interaction, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"report_progress\",\"content\":\"已完成...\"}"),
            ToolDefinition(name: "task_complete", displayName: "Task Complete", description: "标记任务完成并给出摘要。", category: .interaction, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"task_complete\",\"content\":\"完成摘要\"}"),
            ToolDefinition(name: "load_skill", displayName: "Load Skill", description: "按需加载指定 Skill 提示词和附带参考文件。", category: .readOnly, requiresConfirmation: false, inputSchemaHint: "{\"tool\":\"load_skill\",\"skill\":\"Skill 名称\",\"files\":[\"relative/path.ext\"]}")
        ]

        for server in settings.mcpServers where settings.enableMCP && server.isActive {
            let name = "mcp_\(server.name.replacingOccurrences(of: #"[^A-Za-z0-9_]+"#, with: "_", options: .regularExpression))"
            tools.append(ToolDefinition(name: name, displayName: "MCP: \(server.name)", description: server.description.isEmpty ? "MCP 服务器工具入口。" : server.description, category: .mcp, requiresConfirmation: !server.autoApprove, inputSchemaHint: "{\"tool\":\"\(name)\",\"query\":\"任务描述\"}"))
        }
        return tools
    }

    func definition(named name: String) -> ToolDefinition? {
        definitions.first { $0.name == name }
    }

    func extractInvocations(from text: String) -> [ToolInvocation] {
        extractJSONObjects(from: text).compactMap { jsonText in
            guard let data = jsonText.data(using: .utf8), let request = try? JSONDecoder().decode(BuiltinToolRequest.self, from: data) else { return nil }
            guard definition(named: request.tool) != nil || request.tool.hasPrefix("mcp_") else { return nil }
            return ToolInvocation(id: UUID().uuidString, name: request.tool, input: request, rawJSON: jsonText)
        }
    }

    func displayTextByHidingInvocations(in text: String) -> String {
        var displayText = text
        for invocation in extractInvocations(from: text) {
            displayText = displayText.replacingOccurrences(of: invocation.rawJSON, with: "")
        }
        return displayText
            .replacingOccurrences(of: #"(?m)^\s*```(?:json)?\s*```\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func permissionDecision(for invocation: ToolInvocation) -> ToolPermissionDecision {
        guard let definition = definition(named: invocation.name) else {
            if invocation.name.hasPrefix("mcp_") {
                return ToolPermissionDecision(behavior: .ask, reason: "MCP 工具需要确认。")
            }
            return ToolPermissionDecision(behavior: .deny, reason: "未知工具：\(invocation.name)")
        }
        if !definition.requiresConfirmation { return ToolPermissionDecision(behavior: .allow, reason: nil) }
        if definition.category == .mcp, settings.mcpServers.contains(where: { invocation.name == "mcp_\($0.name.replacingOccurrences(of: #"[^A-Za-z0-9_]+"#, with: "_", options: .regularExpression))" && $0.autoApprove }) {
            return ToolPermissionDecision(behavior: .allow, reason: "MCP 服务器已配置自动批准。")
        }
        return ToolPermissionDecision(behavior: .ask, reason: "该工具可能修改文件、运行命令或调用外部 MCP。")
    }

    func promptInstructions(workspacePath: String?) -> String {
        let rows = definitions.map { tool in
            "- \(tool.name) [\(tool.category.rawValue)]：\(tool.description) 示例：\(tool.inputSchemaHint)"
        }.joined(separator: "\n")
        let workspace = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "\n当前工作区：\(workspacePath!)。运行 terminal 时默认 cwd 为该目录。" : ""
        return """
        你可以通过 Easy Chat 工具系统完成任务。严格遵守：
        - 需要调用工具时，只输出一个 JSON 对象，不要包裹代码块。
        - JSON 必须包含 tool 字段，并符合对应示例的字段名。
        - readOnly/web 工具会直接执行；edit/execution/mcp 工具会先请求用户确认。
        - 工具结果会回传给你；收到结果后继续推理或给出最终答案。
        - 不要输出 {\"cmd\": ...}，命令必须使用 terminal。
        \(workspace)

        可用工具：
        \(rows)
        """
    }

    private func extractJSONObjects(from text: String) -> [String] {
        var objects: [String] = []
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]
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
                    let object = String(text[objectStart...index])
                    if object.contains("\"tool\"") || object.contains("\"cmd\"") { objects.append(object) }
                    startIndex = nil
                }
            }
        }
        return objects
    }
}
