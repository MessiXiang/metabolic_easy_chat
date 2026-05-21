//
//  OpenAICompatibleClient.swift
//  easy_chat
//
//  Created by GitHub Copilot on 2026/5/19.
//

import Foundation

final class OpenAICompatibleClient {
    private let settings: ProviderSettings
    private let session: URLSession

    init(settings: ProviderSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func sendChat(messages: [ChatMessage]) async throws -> ChatMessage {
        if settings.useResponsesAPI {
            do {
                return try await sendResponses(messages: messages)
            } catch let error as ChatError {
                if shouldFallbackToChatCompletions(for: error) {
                    return try await sendChatCompletions(messages: messages)
                }
                throw error
            }
        }
        return try await sendChatCompletions(messages: messages)
    }

    func fetchModels() async throws -> [String] {
        let data = try await get(path: settings.modelsPath)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = response.data.map(\.id).sorted()
        return models.isEmpty ? settings.availableModels : models
    }

    func generateImage(prompt: String, size: String) async throws -> ChatMessage {
        let requestBody: [String: Any] = [
            "model": settings.imageModel,
            "prompt": prompt,
            "size": size,
            "n": 1
        ]

        let data = try await post(path: settings.imageGenerationsPath, jsonObject: requestBody, timeout: 300)
        let response = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
        let images = try await response.data.asyncMap { imageData in
            try await normalizedImage(from: imageData)
        }

        guard !images.isEmpty else { throw ChatError.emptyResponse }
        let text = images.compactMap(\.revisedPrompt).first ?? "已生成图片。"
        return ChatMessage(role: .assistant, text: text, images: images)
    }

    private func sendResponses(messages: [ChatMessage]) async throws -> ChatMessage {
        var requestBody: [String: Any] = [
            "model": settings.chatModel,
            "input": messages.map(responseInputItem)
        ]
        applyCommonParameters(to: &requestBody, maxTokenKey: "max_output_tokens")
        applyResponsesTools(to: &requestBody)
        applyInstructionAddons(to: &requestBody)

        let data: Data
        do {
            data = try await post(path: settings.responsesPath, jsonObject: requestBody)
        } catch let error as ChatError {
            if shouldRetryWithoutWebSearch(for: error, requestBody: requestBody) {
                var fallbackBody = requestBody
                removeWebSearchTool(from: &fallbackBody)
                data = try await post(path: settings.responsesPath, jsonObject: fallbackBody)
            } else {
                throw error
            }
        }
        let response = try JSONDecoder().decode(ResponsesAPIResponse.self, from: data)
        let text = response.outputText
        guard !text.isEmpty else { throw ChatError.emptyResponse }
        return ChatMessage(role: .assistant, text: text)
    }

    private func sendChatCompletions(messages: [ChatMessage]) async throws -> ChatMessage {
        var mappedMessages = messages.map(chatCompletionMessage)
        if let developerMessage = developerInstructionMessage() {
            mappedMessages.insert(developerMessage, at: 0)
        }

        var requestBody: [String: Any] = [
            "model": settings.chatModel,
            "messages": mappedMessages
        ]
        applyCommonParameters(to: &requestBody, maxTokenKey: "max_completion_tokens")
        applyChatCompletionTools(to: &requestBody)

        let data = try await post(path: settings.chatCompletionsPath, jsonObject: requestBody)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw ChatError.emptyResponse }
        return ChatMessage(role: .assistant, text: text)
    }

    private func shouldFallbackToChatCompletions(for error: ChatError) -> Bool {
        guard case let .httpError(code, body) = error else { return false }
        guard code == 400 || code == 500 || code == 502 else { return false }
        let lowercasedBody = body.lowercased()
        return lowercasedBody.contains("bad_response_body")
            || lowercasedBody.contains("invalid character")
            || lowercasedBody.contains("responses")
            || lowercasedBody.contains("unsupported")
    }

    private func post(path: String, jsonObject: [String: Any], timeout: TimeInterval = 60) async throws -> Data {
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.missingAPIKey
        }

        let body = try JSONSerialization.data(withJSONObject: jsonObject)
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ChatError.httpError(http.statusCode, bodyText)
        }
        return data
    }

    private func get(path: String) async throws -> Data {
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.missingAPIKey
        }

        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ChatError.httpError(http.statusCode, bodyText)
        }
        return data
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let baseURL = URL(string: settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ChatError.invalidBaseURL
        }

        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            return absoluteURL
        }

        var normalizedPath = path
        if !normalizedPath.hasPrefix("/") {
            normalizedPath = "/" + normalizedPath
        }
        return baseURL.appending(path: normalizedPath)
    }

    private func chatCompletionMessage(_ message: ChatMessage) -> [String: Any] {
        let text = textWithAttachments(message)
        if message.images.isEmpty {
            return ["role": message.role.rawValue, "content": text]
        }

        var content: [[String: Any]] = []
        let visualText = visualInputText(for: message, text: text)
        if !visualText.isEmpty {
            content.append(["type": "text", "text": visualText])
        }
        for image in message.images {
            content.append([
                "type": "image_url",
                "image_url": ["url": image.dataURL]
            ])
        }
        return ["role": visualInputRole(for: message), "content": content]
    }

    private func responseInputItem(_ message: ChatMessage) -> [String: Any] {
        var content: [[String: Any]] = []
        let text = textWithAttachments(message)
        let visualText = message.images.isEmpty ? text : visualInputText(for: message, text: text)
        if !visualText.isEmpty {
            content.append(["type": inputTextType(for: message.images.isEmpty ? message.role : .user), "text": visualText])
        }
        for image in message.images {
            content.append(["type": "input_image", "image_url": image.dataURL])
        }
        return ["role": visualInputRole(for: message), "content": content]
    }

    private func visualInputRole(for message: ChatMessage) -> String {
        message.images.isEmpty ? message.role.rawValue : ChatRole.user.rawValue
    }

    private func visualInputText(for message: ChatMessage, text: String) -> String {
        guard !message.images.isEmpty else { return text }
        let prefix = message.role == .assistant ? "上文 AI 生成/返回的图片，作为视觉上下文提供给你。" : "用户上传的图片。"
        return [prefix, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func textWithAttachments(_ message: ChatMessage) -> String {
        guard !message.attachments.isEmpty else { return message.text }
        let attachmentText = message.attachments.map { attachment in
            var lines = [
                "文件：\(attachment.name)",
                "MIME：\(attachment.mimeType)",
                "大小：\(attachment.byteCount) bytes",
                "本地路径：\(attachment.sourcePath ?? "不可用")",
                "Base64：\(attachment.base64Data.prefix(12_000))\(attachment.base64Data.count > 12_000 ? "…" : "")"
            ]
            if let preview = attachment.textPreview, !preview.isEmpty {
                lines.append("文本预览：\n\(preview)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n---\n\n")
        return [message.text, "附件内容：\n\(attachmentText)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func inputTextType(for role: ChatRole) -> String {
        role == .assistant ? "output_text" : "input_text"
    }

    private func applyCommonParameters(to requestBody: inout [String: Any], maxTokenKey: String) {
        requestBody["temperature"] = settings.temperature
        requestBody["top_p"] = settings.topP
        requestBody[maxTokenKey] = settings.maxOutputTokens

        if settings.enableReasoning {
            requestBody["reasoning"] = ["effort": settings.reasoningEffort]
        }
    }

    private func applyResponsesTools(to requestBody: inout [String: Any]) {
        var tools: [[String: Any]] = []
        if settings.enableWebSearch, shouldUseResponsesWebSearchTool {
            tools.append(["type": settings.responsesWebSearchToolType])
        }
        tools.append(contentsOf: mcpTools())
        if !tools.isEmpty {
            requestBody["tools"] = tools
        }
        applyProviderNativeWebSearch(to: &requestBody, endpoint: .responses)
    }

    private func shouldRetryWithoutWebSearch(for error: ChatError, requestBody: [String: Any]) -> Bool {
        guard settings.enableWebSearch, settings.disableWebSearchOnUnsupported else { return false }
        guard case let .httpError(code, body) = error, code == 400 else { return false }
        guard body.localizedCaseInsensitiveContains("Unsupported tool type") || body.localizedCaseInsensitiveContains("web_search") else { return false }
        guard let tools = requestBody["tools"] as? [[String: Any]] else { return false }
        return tools.contains { ($0["type"] as? String) == settings.responsesWebSearchToolType }
    }

    private func removeWebSearchTool(from requestBody: inout [String: Any]) {
        guard var tools = requestBody["tools"] as? [[String: Any]] else { return }
        tools.removeAll { ($0["type"] as? String) == settings.responsesWebSearchToolType }
        if tools.isEmpty {
            requestBody.removeValue(forKey: "tools")
        } else {
            requestBody["tools"] = tools
        }
    }

    private func applyChatCompletionTools(to requestBody: inout [String: Any]) {
        applyProviderNativeWebSearch(to: &requestBody, endpoint: .chatCompletions)
    }

    private enum ChatEndpointKind {
        case responses
        case chatCompletions
    }

    private var resolvedWebSearchMode: BuiltinWebSearchMode {
        guard settings.builtinWebSearchMode == .auto else { return settings.builtinWebSearchMode }
        let base = settings.baseURL.lowercased()
        let model = settings.chatModel.lowercased()
        if base.contains("openrouter") || model.contains(":online") {
            return .openRouterPlugin
        }
        if base.contains("dashscope") || base.contains("aliyun") || model.hasPrefix("qwen") {
            return .dashScope
        }
        if base.contains("hunyuan") || model.contains("hunyuan") {
            return .hunyuan
        }
        if base.contains("poe.com") {
            return .poe
        }
        return settings.useResponsesAPI ? .openAIResponsesTool : .openAIChatOptions
    }

    private var shouldUseResponsesWebSearchTool: Bool {
        settings.enableWebSearch && resolvedWebSearchMode == .openAIResponsesTool
    }

    private func applyProviderNativeWebSearch(to requestBody: inout [String: Any], endpoint: ChatEndpointKind) {
        guard settings.enableWebSearch else { return }

        switch resolvedWebSearchMode {
        case .auto, .openAIResponsesTool:
            break
        case .openAIChatOptions:
            requestBody["web_search_options"] = ["search_context_size": openAISearchContextSize]
        case .openRouterPlugin:
            requestBody["plugins"] = [["id": "web", "max_results": settings.webSearchMaxResults]]
            requestBody["web_search_options"] = ["max_results": settings.webSearchMaxResults]
        case .dashScope:
            requestBody["enable_search"] = true
            requestBody["search_options"] = ["forced_search": true]
        case .hunyuan:
            requestBody["enable_enhancement"] = true
            requestBody["citation"] = true
            requestBody["search_info"] = true
        case .poe:
            requestBody["extra_body"] = ["web_search": true]
        }

        if endpoint == .responses, resolvedWebSearchMode == .openAIChatOptions {
            requestBody["web_search_options"] = ["search_context_size": openAISearchContextSize]
        }
    }

    private var openAISearchContextSize: String {
        if settings.webSearchMaxResults <= 33 { return "low" }
        if settings.webSearchMaxResults <= 66 { return "medium" }
        return "high"
    }

    private func applyInstructionAddons(to requestBody: inout [String: Any]) {
        let addons = instructionAddons()
        if !addons.isEmpty {
            requestBody["instructions"] = addons
        }
    }

    private func developerInstructionMessage() -> [String: Any]? {
        let addons = instructionAddons()
        guard !addons.isEmpty else { return nil }
        return ["role": "developer", "content": addons]
    }

    private func instructionAddons() -> String {
        var sections: [String] = []
        if settings.enableBuiltinTools {
            sections.append(ToolInvocationService(settings: settings).promptInstructions(workspacePath: settings.workspacePath))
        }
        if settings.exposeWorkspaceToAI, !settings.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("当前 Easy Chat 工作区：\(settings.workspacePath)。用户界面内置文件列表、文本预览和类 VS Code 终端；本地终端默认 pwd 是该工作区。需要在工作区运行项目命令时使用 terminal；需要读取可见终端历史时使用 terminal_read。")
        }
        if settings.enableSkills {
            let enabledSkills = settings.skills.filter(\.isEnabled)
            var skillLines = enabledSkills.map { skill in
                skillInstructionLine(for: skill)
            }
            if !settings.skillsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                skillLines.append(settings.skillsText)
            }
            if !skillLines.isEmpty {
                let skillSection = """
                可用 Skills（它们只是按需加载的提示词）：
                \(skillLines.joined(separator: "\n\n"))

                当用户任务适合某个 Skill 时，先调用 JSON：{\"tool\": \"load_skill\", \"skill\": \"Skill 名称\"}，读取完整提示词后再继续。需要指定附带文件时使用 files 数组：{\"tool\": \"load_skill\", \"skill\": \"Skill 名称\", \"files\": [\"relative/path.ext\"]}。
                """
                sections.append(skillSection)
            }
        }
        if settings.enableMCP {
            var mcpLines = selectedMCPServers().map { server in
                "- \(server.name) [\(server.type.title)]：\(server.description) \(server.url.isEmpty ? server.command : server.url)"
            }
            if !settings.mcpServersText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mcpLines.append(settings.mcpServersText)
            }
            if !mcpLines.isEmpty {
                sections.append("MCP 服务器配置与可用工具说明：\n\(mcpLines.joined(separator: "\n"))")
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private func skillInstructionLine(for skill: SkillConfig) -> String {
        let fileCatalog = skill.files.isEmpty ? "无附带文件" : skill.files.map { "\($0.relativePath) (\($0.byteCount) bytes)" }.joined(separator: ", ")
        let previewLimit = max(120, settings.skillCatalogPreviewCharacters)
        let preview = String(skill.content.prefix(previewLimit))
        return "- \(skill.name)：\(skill.description)\n文件目录：\(fileCatalog)\n提示词预览：\n\(preview)\(skill.content.count > previewLimit ? "…" : "")"
    }

    private func mcpTools() -> [[String: Any]] {
        guard settings.enableMCP, settings.mcpMode != .disabled else { return [] }
        let structuredTools: [[String: Any]] = selectedMCPServers().compactMap { server in
            guard server.type != .stdio, !server.url.isEmpty else { return nil }
            return [
                "type": "mcp",
                "server_label": server.name,
                "server_url": server.url,
                "require_approval": server.autoApprove ? "never" : "always"
            ]
        }

        let textTools: [[String: Any]] = settings.mcpServersText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { server in
                ["type": "mcp", "server_label": server, "server_url": server]
            }

        return structuredTools + textTools
    }

    private func selectedMCPServers() -> [MCPServerConfig] {
        guard settings.enableMCP else { return [] }
        switch settings.mcpMode {
        case .disabled:
            return []
        case .auto:
            return settings.mcpServers.filter(\.isActive)
        case .manual:
            return settings.mcpServers.filter { $0.isActive && $0.isSelected }
        }
    }

    private func normalizedImage(from imageData: ImageGenerationResponse.ImageData) async throws -> ChatImage {
        if let base64 = imageData.b64JSON, !base64.isEmpty {
            return ChatImage(base64Data: base64, mimeType: "image/png", sourceURL: imageData.url, revisedPrompt: imageData.revisedPrompt)
        }

        guard let urlString = imageData.url, let url = URL(string: urlString) else {
            throw ChatError.unsupportedImageURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ChatError.httpError(http.statusCode, "图片下载失败：\(urlString)")
        }

        let mimeType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first ?? "image/png"
        return ChatImage(base64Data: data.base64EncodedString(), mimeType: mimeType, sourceURL: urlString, revisedPrompt: imageData.revisedPrompt)
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct ResponsesAPIResponse: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let type: String?
            let text: String?
        }
        let content: [ContentItem]?
    }

    let outputTextValue: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputTextValue = "output_text"
        case output
    }

    var outputText: String {
        if let outputTextValue, !outputTextValue.isEmpty {
            return outputTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct ImageGenerationResponse: Decodable {
    struct ImageData: Decodable {
        let b64JSON: String?
        let url: String?
        let revisedPrompt: String?

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
            case url
            case revisedPrompt = "revised_prompt"
        }
    }

    let data: [ImageData]
}
