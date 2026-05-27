//
//  ChatModels.swift
//  metabolic_easy_chat
//
//  Created by GitHub Copilot on 2026/5/19.
//

import AppKit
import Foundation

enum ChatRole: String, Codable, CaseIterable {
    case system
    case user
    case assistant

    var title: String {
        switch self {
        case .system: "System"
        case .user: "你"
        case .assistant: "AI"
        }
    }

    var icon: String {
        switch self {
        case .system: "gearshape.fill"
        case .user: "person.crop.circle.fill"
        case .assistant: "sparkles"
        }
    }
}
struct ResolvedTerminalCommand {
    var executable: String
    var args: [String]
    var displayCommand: String
}

struct TerminalExecutionResult {
    var output: String
    var status: ToolRunStatus
    var exitCode: Int32
}

struct MetabolismSession: Codable, Equatable {
    var originalWorkspacePath: String
    var originalWorkspaceBookmark: Data?
    var workspacePath: String
    var branchName: String
    var githubUser: String
    var repositoryURL: String
    var startedAt = Date()
    var isGitHubReady = false

    var displayStatus: String {
        isGitHubReady ? "GitHub 已就绪" : "等待 GitHub CLI 登录"
    }
}

enum ComposerMode: String, CaseIterable, Identifiable {
    case chat
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "对话"
        case .image: "画图"
        }
    }

    var icon: String {
        switch self {
        case .chat: "text.bubble.fill"
        case .image: "photo.artframe"
        }
    }
}

struct ChatImage: Identifiable, Codable, Hashable {
    var id = UUID()
    var base64Data: String
    var mimeType: String
    var sourceURL: String?
    var revisedPrompt: String?

    var dataURL: String {
        "data:\(mimeType);base64,\(base64Data)"
    }

    var nsImage: NSImage? {
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return NSImage(data: data)
    }
}

struct ChatAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var mimeType: String
    var base64Data: String
    var textPreview: String?
    var byteCount: Int
    var sourcePath: String?
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var role: ChatRole
    var text: String
    var images: [ChatImage] = []
    var attachments: [ChatAttachment] = []
    var toolRuns: [ToolRun] = []
    var toolInvocations: [ToolInvocationRecord] = []
    var diffs: [FileDiffHunk] = []
    var tokenCount: Int?
    var isToolResult: Bool = false
    var isIntermediateResponse: Bool = false
    var createdAt = Date()
}

enum ToolRunStatus: String, Codable, Hashable {
    case running
    case completed
    case failed
}

struct ToolRun: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var output: String
    var status: ToolRunStatus
    var createdAt = Date()
}

struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage]
    var createdAt = Date()
    var updatedAt = Date()
}

enum MCPServerType: String, Codable, CaseIterable, Identifiable {
    case streamableHTTP
    case sse
    case stdio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .streamableHTTP: "Streamable HTTP"
        case .sse: "SSE"
        case .stdio: "stdio"
        }
    }
}

enum MCPMode: String, Codable, CaseIterable, Identifiable {
    case disabled
    case auto
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: "关闭"
        case .auto: "自动"
        case .manual: "手动选择"
        }
    }
}

enum BuiltinWebSearchMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case openAIResponsesTool
    case openAIChatOptions
    case openRouterPlugin
    case dashScope
    case hunyuan
    case poe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .openAIResponsesTool: "OpenAI Responses Tool"
        case .openAIChatOptions: "OpenAI Chat Options"
        case .openRouterPlugin: "OpenRouter Plugin"
        case .dashScope: "DashScope enable_search"
        case .hunyuan: "Hunyuan enhancement"
        case .poe: "Poe extra_body"
        }
    }
}

struct MCPServerConfig: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var description: String
    var type: MCPServerType
    var url: String
    var command: String
    var args: String
    var headers: String
    var isActive: Bool
    var isSelected: Bool
    var autoApprove: Bool

    static var examples: [MCPServerConfig] {
        [
            MCPServerConfig(name: "Context7", description: "文档和库上下文工具", type: .streamableHTTP, url: "https://mcp.context7.com/mcp", command: "", args: "", headers: "", isActive: true, isSelected: false, autoApprove: false),
            MCPServerConfig(name: "本地 stdio", description: "示例：npx -y mcp-server-example", type: .stdio, url: "", command: "npx", args: "-y mcp-server-example", headers: "", isActive: false, isSelected: false, autoApprove: false)
        ]
    }
}

struct SkillConfig: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var description: String
    var content: String
    var folderName: String = ""
    var localFolderPath: String = ""
    var files: [SkillFile] = []
    var isEnabled: Bool

    static var examples: [SkillConfig] {
        [
            SkillConfig(name: "UI/UX Reviewer", description: "检查界面层级、对比度、交互状态。", content: "当用户要求改进 UI 时，优先检查信息层级、留白、对比度、焦点状态和一致性。", isEnabled: false),
            SkillConfig(name: "Code Helper", description: "输出更稳健的代码修改建议。", content: "修改代码前先定位上下文；优先保持现有架构；说明兼容性风险。", isEnabled: false)
        ]
    }
}

struct SecurityScopedBookmark: Codable, Equatable, Hashable {
    var path: String
    var bookmarkData: Data
}

struct SkillFile: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var relativePath: String
    var content: String
    var byteCount: Int
}

struct WorkspaceFileItem: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var relativePath: String
    var isDirectory: Bool
    var depth: Int
}

struct TerminalTextStyle: Hashable {
    var foregroundIndex: Int?
    var backgroundIndex: Int?
    var isBold = false
    var isDim = false
    var isUnderlined = false
    var isInverse = false

    static let normal = TerminalTextStyle()
}

struct TerminalCell: Hashable {
    var text: String
    var style: TerminalTextStyle = .normal
}

struct TerminalLine: Identifiable, Hashable {
    var id = UUID()
    var text: String
    var kind: TerminalLineKind
    var createdAt = Date()
}

struct WorkspaceTerminalSession: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var workingDirectory: String
    var command: String
    var lines: [TerminalLine] = []
    var screen = TerminalScreen()
    var isRunning: Bool = false
    var createdAt = Date()

    var statusText: String {
        isRunning ? "运行中" : "空闲"
    }

    var transcript: String {
        lines.map { line in
            switch line.kind {
            case .input:
                return line.text
            case .output:
                return line.text
            case .system:
                return "[system] \(line.text)"
            case .error:
                return "[error] \(line.text)"
            }
        }.joined(separator: "\n")
    }
}

struct TerminalScreen: Hashable {
    var lines: [String] = [""]
    var styledLines: [[TerminalCell]] = [[]]
    var cursorRow = 0
    var cursorColumn = 0
    var currentStyle = TerminalTextStyle.normal

    init(lines: [String] = [""], cursorRow: Int = 0, cursorColumn: Int = 0, currentStyle: TerminalTextStyle = .normal) {
        self.lines = lines
        self.styledLines = lines.map { line in line.map { TerminalCell(text: String($0), style: currentStyle) } }
        self.cursorRow = cursorRow
        self.cursorColumn = cursorColumn
        self.currentStyle = currentStyle
    }

    var visibleLines: [String] {
        Array(lines.suffix(120))
    }

    var visibleStyledLines: [[TerminalCell]] {
        Array(styledLines.suffix(120))
    }
}

enum TerminalLineKind: String, Codable, Hashable {
    case input
    case output
    case system
    case error
}

struct ProviderSettings: Codable, Equatable {
    var baseURL = "https://api.openai.com"
    var apiKey = ""
    var availableModels: [String] = ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini", "o4-mini"]
    var chatModel = "gpt-4.1-mini"
    var imageModel = "gpt-image-1"
    var temperature = 0.7
    var topP = 1.0
    var maxOutputTokens = 4096
    var reasoningEffort = "medium"
    var enableReasoning = false
    var enableWebSearch = false
    var builtinWebSearchMode: BuiltinWebSearchMode = .auto
    var webSearchMaxResults = 50
    var responsesWebSearchToolType = "web_search_preview"
    var disableWebSearchOnUnsupported = true
    var enableMCP = false
    var mcpMode: MCPMode = .manual
    var mcpServers: [MCPServerConfig] = MCPServerConfig.examples
    var mcpServersText = ""
    var enableSkills = false
    var skillCatalogPreviewCharacters = 600
    var skills: [SkillConfig] = SkillConfig.examples
    var skillsText = ""
    var exposeWorkspaceToAI = true
    var workspacePath = ""
    var workspaceBookmark: Data?
    var authorizedBookmarks: [SecurityScopedBookmark] = []
    var modelsPath = "/v1/models"
    var responsesPath = "/v1/responses"
    var chatCompletionsPath = "/v1/chat/completions"
    var imageGenerationsPath = "/v1/images/generations"
    var useResponsesAPI = true
    var enableBuiltinTools = true
    var builtinToolTimeout = 20
    var maxToolRounds = 8
    var enableStreaming = true
    var yoloMode = false
    var metabolismSession: MetabolismSession?
}

struct FileDiffHunk: Identifiable, Codable, Hashable {
    var id = UUID()
    var filePath: String
    var oldContent: String
    var newContent: String
    var isApplied: Bool = false
    var isTruncated: Bool = false
}

enum ChatError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case emptyResponse
    case httpError(Int, String)
    case unsupportedImageURL
    case builtinToolFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL 无效。"
        case .missingAPIKey:
            "请先在设置中填写 API Key。"
        case .emptyResponse:
            "接口没有返回可显示的内容。"
        case let .httpError(code, body):
            "请求失败（HTTP \(code)）：\(body)"
        case .unsupportedImageURL:
            "图片 URL 无效或无法下载。"
        case let .builtinToolFailed(message):
            "内置工具执行失败：\(message)"
        }
    }
}
