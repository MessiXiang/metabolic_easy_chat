//
//  ChatViewModel.swift
//  easy_chat
//
//  Created by GitHub Copilot on 2026/5/19.
//

import Foundation
import UniformTypeIdentifiers
import AppKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation]
    @Published var selectedConversationID: Conversation.ID?
    @Published var settings: ProviderSettings
    @Published var inputText = ""
    @Published var composerMode: ComposerMode = .chat
    @Published var imageSize = "1024x1024"
    @Published var isSending = false
    @Published var isFetchingModels = false
    @Published var isShowingSettings = false
    @Published var isShowingAlert = false
    @Published var alertMessage = ""
    @Published var pendingTerminalApproval: TerminalApprovalRequest?
    @Published var pendingImages: [ChatImage] = []
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var workspaceFiles: [WorkspaceFileItem] = []
    @Published var selectedWorkspaceFile: WorkspaceFileItem?
    @Published var selectedWorkspaceFilePreview = ""
    @Published var terminals: [WorkspaceTerminalSession] = []
    @Published var selectedTerminalID: WorkspaceTerminalSession.ID?
    @Published var editingMessageID: ChatMessage.ID?
    @Published var editingText = ""
    @Published var streamingText = ""

    private var activeSecurityScopedURLs: [URL] = []
    private let terminalService = WorkspaceTerminalService()
    private var terminalProcesses: [WorkspaceTerminalSession.ID: Process] = [:]
    private var terminalInputHandles: [WorkspaceTerminalSession.ID: FileHandle] = [:]
    private var activeResponseTask: Task<Void, Never>?
    private var shouldStopResponse = false

    private var isRunningInAppSandbox: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static let conversationsKey = "easy_chat.conversations"
    private static let settingsKey = "easy_chat.providerSettings"

    init() {
        settings = Self.load(key: Self.settingsKey) ?? ProviderSettings()
        conversations = Self.load(key: Self.conversationsKey) ?? [
            Conversation(title: "新对话", messages: [])
        ]
        selectedConversationID = conversations.first?.id
        restorePersistedSecurityScopes()
        migrateImportedSkillsIfNeeded()
        if !settings.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refreshWorkspaceFiles()
        }
        createTerminal(title: "zsh", command: "/bin/zsh", args: ["-i"], startImmediately: true)
    }

    var workspaceURL: URL? {
        let path = settings.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path).standardizedFileURL
    }

    var workspaceDisplayName: String {
        workspaceURL?.lastPathComponent ?? "未打开工作区"
    }

    var selectedTerminal: WorkspaceTerminalSession? {
        guard let selectedTerminalID else { return terminals.first }
        return terminals.first { $0.id == selectedTerminalID }
    }

    var selectedConversation: Conversation? {
        guard let selectedConversationID else { return conversations.first }
        return conversations.first { $0.id == selectedConversationID }
    }

    func startNewConversation() {
        let conversation = Conversation(title: "新对话", messages: [])
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        persistConversations()
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if conversations.isEmpty {
            startNewConversation()
        } else if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }
        persistConversations()
    }

    func deleteMessage(_ message: ChatMessage) {
        guard let index = selectedConversationIndex() else { return }
        conversations[index].messages.removeAll { $0.id == message.id }
        conversations[index].updatedAt = Date()
        persistConversations()
    }

    func startEditingMessage(_ message: ChatMessage) {
        editingMessageID = message.id
        editingText = message.text
    }

    func cancelEditing() {
        editingMessageID = nil
        editingText = ""
    }

    func submitEdit() async {
        guard let messageID = editingMessageID, !isSending else { return }
        guard let conversationIndex = selectedConversationIndex() else { return }
        guard let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }

        let newText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else { return }

        conversations[conversationIndex].messages[messageIndex].text = newText
        if messageIndex + 1 < conversations[conversationIndex].messages.endIndex {
            conversations[conversationIndex].messages.removeSubrange((messageIndex + 1)...)
        }
        conversations[conversationIndex].updatedAt = Date()
        persistConversations()

        editingMessageID = nil
        editingText = ""

        let context = Array(conversations[conversationIndex].messages.prefix(messageIndex + 1))
        startAssistantResponse(context: context, imagePrompt: newText)
    }

    func sendWorkspaceFile(_ item: WorkspaceFileItem) {
        guard !item.isDirectory else { return }
        addFileAttachment(from: item.url)
    }

    func sendWorkspaceFilesToChat(_ items: [WorkspaceFileItem]) {
        for item in items where !item.isDirectory {
            addFileAttachment(from: item.url)
        }
    }

    func handleDroppedFiles(_ urls: [URL]) {
        for url in urls {
            addFileAttachment(from: url)
        }
    }

    func applyDiff(_ diff: FileDiffHunk, in messageID: ChatMessage.ID) {
        guard let conversationIndex = selectedConversationIndex(),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }),
              let diffIndex = conversations[conversationIndex].messages[messageIndex].diffs.firstIndex(where: { $0.id == diff.id }) else { return }

        let filePath = diff.filePath
        let url = URL(fileURLWithPath: filePath).standardizedFileURL
        do {
            try diff.newContent.data(using: .utf8)?.write(to: url, options: .atomic)
            conversations[conversationIndex].messages[messageIndex].diffs[diffIndex].isApplied = true
            persistConversations()
            refreshWorkspaceFiles()
            appendTerminalLine("已应用补丁：\(filePath)", kind: .system, to: selectedTerminalID)
        } catch {
            showAlert("应用补丁失败：\(error.localizedDescription)")
        }
    }

    func revertDiff(_ diff: FileDiffHunk, in messageID: ChatMessage.ID) {
        guard let conversationIndex = selectedConversationIndex(),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }),
              let diffIndex = conversations[conversationIndex].messages[messageIndex].diffs.firstIndex(where: { $0.id == diff.id }) else { return }

        let filePath = diff.filePath
        let url = URL(fileURLWithPath: filePath).standardizedFileURL
        do {
            try diff.oldContent.data(using: .utf8)?.write(to: url, options: .atomic)
            conversations[conversationIndex].messages[messageIndex].diffs[diffIndex].isApplied = false
            persistConversations()
            refreshWorkspaceFiles()
            appendTerminalLine("已回滚补丁：\(filePath)", kind: .system, to: selectedTerminalID)
        } catch {
            showAlert("回滚补丁失败：\(error.localizedDescription)")
        }
    }

    func regenerate(from message: ChatMessage) async {
        guard !isSending, let conversationIndex = selectedConversationIndex() else { return }
        guard let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == message.id }) else { return }

        let context: [ChatMessage]
        let imagePrompt: String

        if message.role == .user {
            context = Array(conversations[conversationIndex].messages.prefix(messageIndex + 1))
            imagePrompt = message.text
            if messageIndex + 1 < conversations[conversationIndex].messages.endIndex {
                conversations[conversationIndex].messages.removeSubrange((messageIndex + 1)...)
            }
        } else {
            let messagesBeforeTarget = Array(conversations[conversationIndex].messages.prefix(messageIndex))
            guard let lastUserMessage = messagesBeforeTarget.last(where: { $0.role == .user }) else {
                showAlert("重新生成需要前面存在用户消息。")
                return
            }

            context = messagesBeforeTarget
            imagePrompt = lastUserMessage.text
            conversations[conversationIndex].messages.removeSubrange(messageIndex...)
        }
        conversations[conversationIndex].updatedAt = Date()
        persistConversations()

        startAssistantResponse(context: context, imagePrompt: imagePrompt)
    }

    func regenerateLastAssistant() async {
        guard let lastAssistant = selectedConversation?.messages.last(where: { $0.role == .assistant }) else {
            showAlert("当前对话还没有可重新生成的 AI 回复。")
            return
        }
        await regenerate(from: lastAssistant)
    }

    func send() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!prompt.isEmpty || !pendingImages.isEmpty || !pendingAttachments.isEmpty), !isSending else { return }

        inputText = ""
        let images = pendingImages
        let attachments = pendingAttachments
        pendingImages = []
        pendingAttachments = []
        var userMessage = ChatMessage(role: .user, text: prompt, images: images, attachments: attachments)
        userMessage.tokenCount = estimateTokenCount(for: userMessage)
        append(userMessage)

        let context = selectedConversation?.messages ?? []
        startAssistantResponse(context: context, imagePrompt: prompt)
    }

    func estimateTokenCount(for message: ChatMessage) -> Int {
        var count = message.text.count / 4
        for attachment in message.attachments {
            count += attachment.byteCount / 4
        }
        for image in message.images {
            count += 85
        }
        return max(count, 1)
    }

    func emergencyStopResponse() {
        shouldStopResponse = true
        activeResponseTask?.cancel()
        activeResponseTask = nil
        isSending = false
        pendingTerminalApproval?.deny()
        pendingTerminalApproval = nil
        terminalProcesses.values.forEach { process in
            if process.isRunning { process.terminate() }
        }
        appendTerminalLine("已急停 AI 响应。", kind: .system, to: selectedTerminalID)
    }

    private func startAssistantResponse(context: [ChatMessage], imagePrompt: String) {
        activeResponseTask?.cancel()
        shouldStopResponse = false
        activeResponseTask = Task { [weak self] in
            await self?.requestAssistantResponse(context: context, imagePrompt: imagePrompt)
        }
    }

    func addImageAttachment(from url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else { throw ChatError.builtinToolFailed("无法访问所选图片。") }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            guard data.count <= 20_000_000 else { throw ChatError.builtinToolFailed("图片过大，请选择 20MB 以内图片。") }
            let mimeType = mimeType(for: url)
            pendingImages.append(ChatImage(base64Data: data.base64EncodedString(), mimeType: mimeType, sourceURL: url.lastPathComponent))
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    func addFileAttachment(from url: URL) {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let mimeType = mimeType(for: url)
            if mimeType.hasPrefix("image/") {
                guard data.count <= 20_000_000 else { throw ChatError.builtinToolFailed("图片过大，请选择 20MB 以内图片。") }
                pendingImages.append(ChatImage(base64Data: data.base64EncodedString(), mimeType: mimeType, sourceURL: url.lastPathComponent))
                return
            }
            guard data.count <= 50_000_000 else { throw ChatError.builtinToolFailed("文件过大，请选择 50MB 以内文件。") }
            let preview = textPreview(from: data)
            pendingAttachments.append(ChatAttachment(name: url.lastPathComponent, mimeType: mimeType, base64Data: data.base64EncodedString(), textPreview: preview, byteCount: data.count, sourcePath: url.path))
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    func removePendingImage(_ image: ChatImage) {
        pendingImages.removeAll { $0.id == image.id }
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func openWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "打开工作区"
        panel.message = "选择一个文件夹作为 Easy Chat 工作区。终端默认 pwd 会设为该目录。"
        if panel.runModal() == .OK, let url = panel.url {
            authorize(url: url, saveAsWorkspace: true)
            persistSettings()
            refreshWorkspaceFiles()
            appendTerminalLine("已打开工作区：\(url.path)", kind: .system, to: selectedTerminalID)
        }
    }

    func authorizeAdditionalAccess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "授权访问"
        panel.message = "选择终端命令需要读取或写入的文件/文件夹，例如 Downloads 中的 docx 或 /tmp 替代目录。"
        if panel.runModal() == .OK {
            panel.urls.forEach { authorize(url: $0, saveAsWorkspace: false) }
            persistSettings()
            let paths = panel.urls.map(\.path).joined(separator: "\n")
            appendTerminalLine("已授权访问：\n\(paths)", kind: .system, to: selectedTerminalID)
        }
    }

    func revealWorkspaceInFinder() {
        guard let workspaceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([workspaceURL])
    }

    func refreshWorkspaceFiles() {
        guard let workspaceURL else {
            workspaceFiles = []
            selectedWorkspaceFile = nil
            selectedWorkspaceFilePreview = ""
            return
        }
        do {
            workspaceFiles = try listWorkspaceFiles(root: workspaceURL)
            if let selectedWorkspaceFile, !FileManager.default.fileExists(atPath: selectedWorkspaceFile.url.path) {
                self.selectedWorkspaceFile = nil
                selectedWorkspaceFilePreview = ""
            }
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    func selectWorkspaceFile(_ item: WorkspaceFileItem) {
        selectedWorkspaceFile = item
        guard !item.isDirectory else {
            selectedWorkspaceFilePreview = "文件夹：\(item.relativePath)"
            return
        }
        do {
            selectedWorkspaceFilePreview = try previewWorkspaceFile(item.url)
        } catch {
            selectedWorkspaceFilePreview = error.localizedDescription
        }
    }

    func newInteractiveTerminal() {
        createTerminal(title: "zsh", command: "/bin/zsh", args: ["-i"], startImmediately: true)
    }

    func newCommandTerminal(commandLine: String, title: String = "task") -> WorkspaceTerminalSession.ID {
        createTerminal(title: title, command: "/bin/zsh", args: ["-lc", commandLine], startImmediately: true)
    }

    func stopSelectedTerminal() {
        guard let id = selectedTerminalID else { return }
        terminalProcesses[id]?.terminate()
    }

    func deleteTerminal(_ terminal: WorkspaceTerminalSession) {
        terminalProcesses[terminal.id]?.terminate()
        terminalProcesses[terminal.id] = nil
        terminalInputHandles[terminal.id] = nil
        terminals.removeAll { $0.id == terminal.id }
        if selectedTerminalID == terminal.id {
            selectedTerminalID = terminals.first?.id
        }
        if terminals.isEmpty {
            createTerminal(title: "zsh", command: "/bin/zsh", args: ["-i"], startImmediately: false)
        }
    }

    func persistSettings() {
        save(settings, key: Self.settingsKey)
    }

    func fetchModels() async {
        guard !isFetchingModels else { return }
        isFetchingModels = true
        do {
            let models = try await OpenAICompatibleClient(settings: settings).fetchModels()
            settings.availableModels = models
            if !models.contains(settings.chatModel), let first = models.first {
                settings.chatModel = first
            }
            persistSettings()
        } catch {
            showAlert(error.localizedDescription)
        }
        isFetchingModels = false
    }

    func addMCPServer() {
        settings.mcpServers.insert(MCPServerConfig(name: "New MCP Server", description: "", type: .streamableHTTP, url: "", command: "", args: "", headers: "", isActive: false, isSelected: true, autoApprove: false), at: 0)
        persistSettings()
    }

    func deleteMCPServer(_ server: MCPServerConfig) {
        settings.mcpServers.removeAll { $0.id == server.id }
        persistSettings()
    }

    func addSkill() {
        settings.skills.insert(SkillConfig(name: "New Skill", description: "", content: "", isEnabled: true), at: 0)
        persistSettings()
    }

    func deleteSkill(_ skill: SkillConfig) {
        deleteImportedSkillFolderIfNeeded(skill)
        settings.skills.removeAll { $0.id == skill.id }
        persistSettings()
    }

    func importSkillFolder(from url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else { throw ChatError.builtinToolFailed("无法访问所选 Skill 文件夹。") }
            defer { url.stopAccessingSecurityScopedResource() }
            let localURL = try copySkillFolderToApplicationSupport(from: url)
            let skill = try loadSkillFolder(from: localURL, originalFolderName: url.lastPathComponent)
            settings.skills.insert(skill, at: 0)
            settings.enableSkills = true
            persistSettings()
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    private func requestAssistantResponse(context: [ChatMessage], imagePrompt: String) async {
        guard !isSending else { return }
        isSending = true
        streamingText = ""
        defer {
            isSending = false
            streamingText = ""
            activeResponseTask = nil
        }
        let shouldGenerateTitle = selectedConversation?.title == "新对话" && context.contains { $0.role == .user }

        do {
            let client = OpenAICompatibleClient(settings: settings)
            var assistantMessage: ChatMessage
            if composerMode == .image {
                assistantMessage = try await client.generateImage(prompt: imagePrompt, size: imageSize)
                try Task.checkCancellation()
                guard !shouldStopResponse else { return }
                append(assistantMessage)
            } else if settings.enableStreaming {
                assistantMessage = try await client.streamChat(messages: context) { [weak self] delta in
                    Task { @MainActor in
                        self?.streamingText += delta
                    }
                }
                try Task.checkCancellation()
                guard !shouldStopResponse else { return }
                // If tool calls detected, truncate to only the JSON portion
                let toolService = ToolInvocationService(settings: settings)
                let invocations = toolService.extractInvocations(from: assistantMessage.text)
                let hasTools = !invocations.isEmpty
                if hasTools {
                    // Keep only the tool JSON, discard any natural language the AI mixed in
                    assistantMessage.text = invocations.map(\.rawJSON).joined()
                    assistantMessage.isIntermediateResponse = true
                }
                let diffs = extractDiffs(from: assistantMessage.text)
                if !diffs.isEmpty { assistantMessage.diffs = diffs }
                append(assistantMessage)
                if hasTools {
                    try await executeToolsIncrementally(from: assistantMessage, context: context + [assistantMessage], client: client)
                }
            } else {
                assistantMessage = try await client.sendChat(messages: context)
                try Task.checkCancellation()
                guard !shouldStopResponse else { return }
                // If tool calls detected, truncate to only the JSON portion
                let toolService = ToolInvocationService(settings: settings)
                let invocations = toolService.extractInvocations(from: assistantMessage.text)
                let hasTools = !invocations.isEmpty
                if hasTools {
                    assistantMessage.text = invocations.map(\.rawJSON).joined()
                    assistantMessage.isIntermediateResponse = true
                }
                let diffs = extractDiffs(from: assistantMessage.text)
                if !diffs.isEmpty { assistantMessage.diffs = diffs }
                append(assistantMessage)
                if hasTools {
                    try await executeToolsIncrementally(from: assistantMessage, context: context + [assistantMessage], client: client)
                }
            }
            if shouldGenerateTitle, !shouldStopResponse, !Task.isCancelled {
                await generateConversationTitle(using: client)
            }
        } catch is CancellationError {
            appendTerminalLine("AI 响应已取消。", kind: .system, to: selectedTerminalID)
        } catch {
            if !shouldStopResponse {
                showAlert(error.localizedDescription)
            }
        }
    }

    /// Execute tools one by one as they are found, feeding results back immediately
    private func executeToolsIncrementally(from message: ChatMessage, context: [ChatMessage], client: OpenAICompatibleClient) async throws {
        guard settings.enableBuiltinTools else { return }
        let toolService = ToolInvocationService(settings: settings)
        let executor = BuiltinToolExecutor(settings: settings)
        var currentMessage = message
        var currentContext = context

        for _ in 0..<max(settings.maxToolRounds, 0) {
            try Task.checkCancellation()
            guard !shouldStopResponse else { return }
            let invocations = Array(toolService.extractInvocations(from: currentMessage.text).prefix(8))
            guard !invocations.isEmpty else { return }

            // Execute each tool invocation immediately as we process them
            var allResults: [BuiltinToolResult] = []
            setToolInvocationRecords(for: currentMessage.id, records: invocations.map { invocation in
                ToolInvocationRecord(id: invocation.id, toolName: invocation.name, displayName: toolDisplayName(invocation.name), input: invocation.rawJSON, output: "", status: .running, isConfirmed: nil, isComplete: false)
            })

            for invocation in invocations {
                try Task.checkCancellation()
                guard !shouldStopResponse else { return }

                let result: BuiltinToolResult
                if isTerminalTool(invocation.name) {
                    let terminalResults = await executeTerminalInvocations([invocation], for: currentMessage.id, toolService: toolService)
                    result = terminalResults.first ?? BuiltinToolResult(title: invocation.name, output: "执行失败", status: .failed)
                } else if invocation.name == "load_skill" {
                    let skillResults = executeLoadSkillInvocations([invocation])
                    result = skillResults.first ?? BuiltinToolResult(title: invocation.name, output: "执行失败", status: .failed)
                } else if invocation.name.hasPrefix("mcp_") {
                    let mcpResults = await executeMCPInvocations([invocation], for: currentMessage.id, toolService: toolService)
                    result = mcpResults.first ?? BuiltinToolResult(title: invocation.name, output: "执行失败", status: .failed)
                } else {
                    // Use the already-parsed request directly instead of re-parsing JSON
                    result = await executor.executeSingleRequest(invocation.input)
                }
                allResults.append(result)

                // Update UI immediately after each tool completes
                mergeToolInvocationResults(for: currentMessage.id, results: [result])
            }

            guard !allResults.isEmpty else { return }

            let resultText = allResults.map { result in
                let statusText = result.status == .completed ? "成功" : "失败"
                return "工具：\(result.title)\n状态：\(statusText)\n输出：\n\(result.output)"
            }.joined(separator: "\n\n---\n\n")

            var toolMessage = ChatMessage(role: .user, text: "以下是工具执行结果。如需继续调用工具，整条回复只输出 JSON，不要有任何其他文字。如果信息已足够，直接用自然语言给出最终答案。\n\n\(resultText)")
            toolMessage.isToolResult = true
            var finalMessage: ChatMessage
            if settings.enableStreaming {
                streamingText = ""
                finalMessage = try await client.streamChat(messages: currentContext + [toolMessage]) { [weak self] delta in
                    Task { @MainActor in self?.streamingText += delta }
                }
                streamingText = ""
            } else {
                finalMessage = try await client.sendChat(messages: currentContext + [toolMessage])
            }
            try Task.checkCancellation()
            guard !shouldStopResponse else { return }
            // If follow-up contains tool calls, truncate to only JSON
            let followUpInvocations = toolService.extractInvocations(from: finalMessage.text)
            if !followUpInvocations.isEmpty {
                finalMessage.text = followUpInvocations.map(\.rawJSON).joined()
                finalMessage.isIntermediateResponse = true
            }
            let followUpDiffs = extractDiffs(from: finalMessage.text)
            if !followUpDiffs.isEmpty { finalMessage.diffs = followUpDiffs }
            append(finalMessage)
            currentContext += [toolMessage, finalMessage]
            currentMessage = finalMessage
        }
    }

    private func extractDiffs(from text: String) -> [FileDiffHunk] {
        guard settings.enableBuiltinTools else { return [] }
        let toolService = ToolInvocationService(settings: settings)
        let invocations = toolService.extractInvocations(from: text)
        var diffs: [FileDiffHunk] = []
        for invocation in invocations {
            guard invocation.name == "write_file" || invocation.name == "replace_string" || invocation.name == "create_file" else { continue }
            guard let path = invocation.input.path else { continue }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let oldContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let newContent: String
            if invocation.name == "replace_string", let oldStr = invocation.input.oldString, let newStr = invocation.input.newString {
                newContent = oldContent.replacingOccurrences(of: oldStr, with: newStr)
            } else if let content = invocation.input.content {
                if invocation.input.append == true {
                    newContent = oldContent + content
                } else {
                    newContent = content
                }
            } else {
                continue
            }
            guard oldContent != newContent else { continue }
            diffs.append(FileDiffHunk(filePath: path, oldContent: oldContent, newContent: newContent))
        }
        return diffs
    }

    private func isTerminalTool(_ name: String) -> Bool {
        name == "terminal" || name == "terminal_read"
    }

    private func toolDisplayName(_ name: String) -> String {
        ToolInvocationService(settings: settings).definition(named: name)?.displayName ?? name
    }

    private func terminalTitle(for request: BuiltinToolRequest) -> String {
        switch request.tool {
        case "terminal":
            return "terminal: \(request.command ?? "")"
        case "terminal_read":
            return "terminal_read"
        default:
            return "terminal: \(request.command ?? "")"
        }
    }

    private func executeTerminalInvocations(_ invocations: [ToolInvocation], for messageID: ChatMessage.ID, toolService: ToolInvocationService) async -> [BuiltinToolResult] {
        var results: [BuiltinToolResult] = []
        for invocation in invocations.prefix(3) {
            let decision = toolService.permissionDecision(for: invocation)
            if case .deny = decision.behavior {
                results.append(BuiltinToolResult(title: terminalTitle(for: invocation.input), output: decision.reason ?? "工具被拒绝。", status: .failed))
                continue
            }
            let result = await executeSkillTerminal(invocation.input, for: messageID)
            results.append(result)
        }
        return results
    }

    private func executeLoadSkillInvocations(_ invocations: [ToolInvocation]) -> [BuiltinToolResult] {
        invocations.prefix(5).map { invocation in
            let output = loadSkillContext(skillName: invocation.input.skill, requestedFiles: invocation.input.files)
            return BuiltinToolResult(title: "load_skill: \(invocation.input.skill ?? "")", output: output, status: output.hasPrefix("未找到") ? .failed : .completed)
        }
    }

    private func loadSkillContext(skillName: String?, requestedFiles: [String]?) -> String {
        guard let skill = resolvedSkill(for: skillName) else { return "未找到 Skill：\(skillName ?? "")" }
        var sections = [
            "Skill：\(skill.name)",
            "描述：\(skill.description)",
            "SKILL.md：\n\(skill.content)"
        ]
        let selectedFiles: [SkillFile]
        if let requestedFiles, !requestedFiles.isEmpty {
            let wanted = Set(requestedFiles.map { $0.lowercased() })
            selectedFiles = skill.files.filter { wanted.contains($0.relativePath.lowercased()) }
        } else {
            selectedFiles = Array(skill.files.prefix(8))
        }
        if !selectedFiles.isEmpty {
            sections.append("附带文件：\n" + selectedFiles.map { file in
                "文件：\(file.relativePath)\n大小：\(file.byteCount) bytes\n\(String(file.content.prefix(12_000)))"
            }.joined(separator: "\n\n---\n\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private func executeMCPInvocations(_ invocations: [ToolInvocation], for messageID: ChatMessage.ID, toolService: ToolInvocationService) async -> [BuiltinToolResult] {
        var results: [BuiltinToolResult] = []
        for invocation in invocations.prefix(3) {
            let decision = toolService.permissionDecision(for: invocation)
            if case .ask = decision.behavior, !settings.yoloMode {
                let approved = await requestTerminalApproval(command: invocation.name, args: [invocation.rawJSON], workingDirectory: workspaceURL?.path ?? FileManager.default.currentDirectoryPath)
                guard approved else {
                    results.append(BuiltinToolResult(title: invocation.name, output: "用户取消 MCP 工具调用。", status: .failed))
                    continue
                }
            }
            results.append(BuiltinToolResult(title: invocation.name, output: "MCP 工具注册与确认流程已就绪。当前版本尚未实现完整 JSON-RPC 会话调用；请在设置中配置 server 后继续接入 tools/list 与 tools/call。\n输入：\n\(invocation.rawJSON)", status: .failed))
        }
        return results
    }

    private func executeSkillTerminal(_ request: BuiltinToolRequest, for messageID: ChatMessage.ID) async -> BuiltinToolResult {
        let title = terminalTitle(for: request)
        if request.tool == "terminal_read" {
            let output = selectedTerminalTranscript()
            return BuiltinToolResult(title: title, output: output.isEmpty ? "当前终端暂无内容。" : output, status: .completed)
        }
        guard let command = request.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return BuiltinToolResult(title: title, output: "terminal 缺少 command。", status: .failed)
        }
        let args = request.args ?? []
        let workingDirectory = workspaceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let environment = terminalEnvironment()
        let resolvedCommand = terminalService.resolve(command: command, args: args, environment: environment)
        let displayCommand = resolvedCommand.displayCommand
        let cwdPath = workingDirectory.path
        updateToolRun(for: messageID, title: title, output: "等待用户批准执行：\ncd \(cwdPath)\n\(displayCommand)", status: .running)
        await ensureAccessForTerminalCommand(displayCommand)
        await ensureExecutableAccessIfNeeded(resolvedCommand.executable)
        let approved = await requestTerminalApproval(command: resolvedCommand.executable, args: resolvedCommand.args, workingDirectory: cwdPath)
        guard approved else {
            return BuiltinToolResult(title: title, output: "用户取消执行。", status: .failed)
        }

        let terminalID = createTerminal(title: "ai command", command: resolvedCommand.executable, args: resolvedCommand.args, workingDirectory: workingDirectory, environment: environment, startImmediately: false)
        appendTerminalLine("pwd: \(cwdPath)", kind: .system, to: terminalID)
        appendTerminalLine("AI 调用：\(displayCommand)", kind: .input, to: terminalID)
        let result = await runProcess(command: resolvedCommand.executable, args: resolvedCommand.args, workingDirectory: workingDirectory, environment: environment, timeout: min(max(request.timeout ?? 120, 5), 600), terminalID: terminalID) { text in
            self.updateToolRun(for: messageID, title: title, output: text, status: .running)
        }
        updateToolRun(for: messageID, title: title, output: result.output, status: result.status)
        return BuiltinToolResult(title: title, output: result.output, status: result.status)
    }

    private func runProcess(command: String, args: [String], workingDirectory: URL?, environment: [String: String], timeout: Int, terminalID: WorkspaceTerminalSession.ID?, onOutput: @escaping @MainActor (String) -> Void) async -> TerminalExecutionResult {
        markTerminal(terminalID, running: true)
        var output = ""
        let result = await terminalService.run(command: command, args: args, workingDirectory: workingDirectory, environment: environment, timeout: timeout) { text in
            Task { @MainActor in
                output += text
                let currentOutput = String(output.suffix(40_000))
                self.appendTerminalChunk(text, to: terminalID)
                onOutput(currentOutput)
            }
        }
        markTerminal(terminalID, running: false)
        onOutput(result.output)
        return result
    }

    @discardableResult
    private func createTerminal(title: String, command: String, args: [String], workingDirectory: URL? = nil, environment: [String: String]? = nil, startImmediately: Bool) -> WorkspaceTerminalSession.ID {
        let cwd = workingDirectory ?? workspaceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var session = WorkspaceTerminalSession(title: title, workingDirectory: cwd.path, command: ([command] + args).joined(separator: " "), lines: [TerminalLine(text: "pwd: \(cwd.path)", kind: .system)], isRunning: false)
        session.screen = TerminalScreen(lines: ["pwd: \(cwd.path)", ""], cursorRow: 1, cursorColumn: 0)
        terminals.append(session)
        selectedTerminalID = session.id
        if startImmediately {
            startInteractiveProcess(for: session.id, command: command, args: args, workingDirectory: cwd, environment: environment ?? terminalEnvironment())
        }
        return session.id
    }

    private func startInteractiveProcess(for id: WorkspaceTerminalSession.ID, command: String, args: [String], workingDirectory: URL, environment: [String: String]) {
        guard terminalProcesses[id] == nil else { return }
        do {
            let runningProcess = try terminalService.startInteractive(command: command, args: args, workingDirectory: workingDirectory, environment: environment) { text in
            Task { @MainActor in self.appendTerminalChunk(text, to: id) }
            } onExit: { exitCode in
            Task { @MainActor in
                self.markTerminal(id, running: false)
                    self.appendTerminalLine("[exit \(exitCode)]", kind: exitCode == 0 ? .system : .error, to: id)
                self.terminalProcesses[id] = nil
                self.terminalInputHandles[id] = nil
                self.refreshWorkspaceFiles()
            }
            }
            terminalProcesses[id] = runningProcess.process
            terminalInputHandles[id] = runningProcess.inputHandle
            markTerminal(id, running: true)
        } catch {
            appendTerminalLine(error.localizedDescription, kind: .error, to: id)
            markTerminal(id, running: false)
        }
    }

    func sendToSelectedTerminal(_ text: String) {
        guard let id = selectedTerminalID, let data = text.data(using: .utf8) else { return }
        ensureSelectedInteractiveTerminalIsRunning()
        terminalInputHandles[id]?.write(data)
    }

    private func ensureSelectedInteractiveTerminalIsRunning() {
        guard let id = selectedTerminalID else { return }
        if terminalProcesses[id] == nil, let terminal = terminals.first(where: { $0.id == id }) {
            startInteractiveProcess(for: id, command: "/bin/zsh", args: ["-i"], workingDirectory: URL(fileURLWithPath: terminal.workingDirectory), environment: terminalEnvironment())
        }
    }

    func approvePendingTerminalExecution() {
        pendingTerminalApproval?.approve()
        pendingTerminalApproval = nil
    }

    func denyPendingTerminalExecution() {
        pendingTerminalApproval?.deny()
        pendingTerminalApproval = nil
    }

    private func requestTerminalApproval(command: String, args: [String], workingDirectory: String) async -> Bool {
        if settings.yoloMode { return true }
        return await withCheckedContinuation { continuation in
            pendingTerminalApproval = TerminalApprovalRequest(command: command, args: args, workingDirectory: workingDirectory) { approved in
                continuation.resume(returning: approved)
            }
        }
    }

    private func updateToolRun(for messageID: ChatMessage.ID, title: String, output: String, status: ToolRunStatus) {
        guard let conversationIndex = selectedConversationIndex(), let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        if let runIndex = conversations[conversationIndex].messages[messageIndex].toolRuns.firstIndex(where: { $0.title == title }) {
            conversations[conversationIndex].messages[messageIndex].toolRuns[runIndex].output = output
            conversations[conversationIndex].messages[messageIndex].toolRuns[runIndex].status = status
        }
        conversations[conversationIndex].updatedAt = Date()
        persistConversations()
    }

    private func terminalEnvironment() -> [String: String] {
        terminalService.environment(pathAdditions: "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    private func selectedTerminalTranscript() -> String {
        guard let selectedTerminal else { return "" }
        return String(selectedTerminal.transcript.suffix(40_000))
    }

    private func ensureExecutableAccessIfNeeded(_ executable: String) async {
        guard isRunningInAppSandbox else { return }
        guard executable.hasPrefix("/"), !isSystemExecutablePath(executable), !isPathAuthorized(executable) else { return }
        appendTerminalLine("命令需要执行外部程序，请在弹出的授权面板中选择该程序或其上级文件夹：\n\(executable)", kind: .system, to: selectedTerminalID)
        requestAccessForPaths([executable])
    }

    private func isSystemExecutablePath(_ path: String) -> Bool {
        path.hasPrefix("/usr/bin/") || path.hasPrefix("/bin/") || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/sbin/")
    }

    private func markMessageAsIntermediate(_ messageID: ChatMessage.ID) {
        guard let conversationIndex = selectedConversationIndex(), let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[conversationIndex].messages[messageIndex].isIntermediateResponse = true
    }

    private func setToolRuns(for messageID: ChatMessage.ID, runs: [ToolRun]) {
        guard let conversationIndex = selectedConversationIndex(), let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[conversationIndex].messages[messageIndex].toolRuns = runs
        conversations[conversationIndex].updatedAt = Date()
        persistConversations()
    }

    private func setToolInvocationRecords(for messageID: ChatMessage.ID, records: [ToolInvocationRecord]) {
        guard let conversationIndex = selectedConversationIndex(), let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[conversationIndex].messages[messageIndex].toolInvocations = records
        conversations[conversationIndex].updatedAt = Date()
        persistConversations()
    }

    private func mergeToolInvocationResults(for messageID: ChatMessage.ID, results: [BuiltinToolResult]) {
        guard let conversationIndex = selectedConversationIndex(), let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        for result in results {
            if let recordIndex = conversations[conversationIndex].messages[messageIndex].toolInvocations.firstIndex(where: { result.title.localizedCaseInsensitiveContains($0.toolName) || result.title.localizedCaseInsensitiveContains($0.displayName) }) {
                conversations[conversationIndex].messages[messageIndex].toolInvocations[recordIndex].output = result.output
                conversations[conversationIndex].messages[messageIndex].toolInvocations[recordIndex].status = result.status
                conversations[conversationIndex].messages[messageIndex].toolInvocations[recordIndex].isComplete = true
                if conversations[conversationIndex].messages[messageIndex].toolInvocations[recordIndex].isConfirmed == nil {
                    conversations[conversationIndex].messages[messageIndex].toolInvocations[recordIndex].isConfirmed = result.status == .completed
                }
            }
        }
        conversations[conversationIndex].updatedAt = Date()
        persistConversations()
    }

    private func generateConversationTitle(using client: OpenAICompatibleClient) async {
        guard let index = selectedConversationIndex(), conversations[index].title == "新对话" else { return }
        let messages = conversations[index].messages.prefix(6).map { message in
            "\(message.role.title)：\(message.text)"
        }.joined(separator: "\n")
        guard !messages.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            let prompt = ChatMessage(role: .user, text: """
            请为下面这段对话生成一个简洁中文标题。
            要求：
            - 只输出标题，不要解释，不要加引号。
            - 8 到 18 个汉字左右。
            - 不要使用“新对话”。

            对话：
            \(messages)
            """)
            let response = try await client.sendChat(messages: [prompt])
            let title = cleanGeneratedTitle(response.text)
            guard !title.isEmpty, let currentIndex = selectedConversationIndex(), conversations[currentIndex].title == "新对话" else { return }
            conversations[currentIndex].title = title
            conversations[currentIndex].updatedAt = Date()
            persistConversations()
        } catch {
            guard let currentIndex = selectedConversationIndex(), conversations[currentIndex].title == "新对话", let firstUser = conversations[currentIndex].messages.first(where: { $0.role == .user }) else { return }
            conversations[currentIndex].title = title(from: firstUser.text)
            persistConversations()
        }
    }

    private func append(_ message: ChatMessage) {
        guard let index = selectedConversationIndex() else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()

        persistConversations()
    }

    private func selectedConversationIndex() -> Int? {
        if let selectedConversationID, let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) {
            return index
        }
        if conversations.isEmpty {
            startNewConversation()
        }
        selectedConversationID = conversations.first?.id
        return conversations.indices.first
    }

    private func title(from text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        if clean.count <= 18 { return clean }
        return String(clean.prefix(18)) + "…"
    }

    private func cleanGeneratedTitle(_ text: String) -> String {
        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("```") {
            let lines = title.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            title = lines.dropFirst().dropLast(lines.last?.hasPrefix("```") == true ? 1 : 0).joined(separator: "\n")
        }
        title = title.split(separator: "\n").first.map(String.init) ?? title
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'“”‘’#：:"))
        if title.count > 24 { title = String(title.prefix(24)) + "…" }
        return title == "新对话" ? "" : title
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        isShowingAlert = true
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    private func textPreview(from data: Data) -> String? {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        return text.map { String($0.prefix(20_000)) }
    }

    private func listWorkspaceFiles(root: URL) throws -> [WorkspaceFileItem] {
        var items: [WorkspaceFileItem] = []
        try collectWorkspaceFiles(root: root, directory: root, depth: 0, output: &items)
        return items
    }

    private func collectWorkspaceFiles(root: URL, directory: URL, depth: Int, output: inout [WorkspaceFileItem]) throws {
        guard depth <= 5 else { return }
        let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { ![".git", "node_modules", "DerivedData", ".build"].contains($0.lastPathComponent) }
            .sorted { left, right in
                let leftIsDirectory = ((try? left.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
                let rightIsDirectory = ((try? right.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
                if leftIsDirectory != rightIsDirectory { return leftIsDirectory && !rightIsDirectory }
                return left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
            }
        for child in children.prefix(120) {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let relativePath = child.path.replacingOccurrences(of: root.path + "/", with: "")
            output.append(WorkspaceFileItem(url: child, relativePath: relativePath, isDirectory: isDirectory, depth: depth))
            if isDirectory { try collectWorkspaceFiles(root: root, directory: child, depth: depth + 1, output: &output) }
            if output.count >= 1_000 { return }
        }
    }

    private func previewWorkspaceFile(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 2_000_000 else { throw ChatError.builtinToolFailed("文件过大，仅支持预览 2MB 以内文本文件。") }
        guard let text = textPreview(from: data) else { throw ChatError.builtinToolFailed("无法按文本预览文件。") }
        return text
    }

    private func appendTerminalLine(_ text: String, kind: TerminalLineKind, to terminalID: WorkspaceTerminalSession.ID?) {
        guard let index = terminalIndex(for: terminalID) else { return }
        terminals[index].lines.append(TerminalLine(text: text, kind: kind))
        if kind == .output || kind == .input {
            applyTerminalOutput(text, to: index)
        } else {
            applyTerminalOutput("\r\n\(text)\r\n", to: index)
        }
        if terminals[index].lines.count > 500 {
            terminals[index].lines.removeFirst(terminals[index].lines.count - 500)
        }
    }

    private func appendTerminalChunk(_ text: String, to terminalID: WorkspaceTerminalSession.ID?) {
        guard let index = terminalIndex(for: terminalID) else { return }
        applyTerminalOutput(text, to: index)
        if terminals[index].lines.last?.kind == .output {
            terminals[index].lines[terminals[index].lines.count - 1].text += text
            if terminals[index].lines[terminals[index].lines.count - 1].text.count > 60_000 {
                terminals[index].lines[terminals[index].lines.count - 1].text = String(terminals[index].lines[terminals[index].lines.count - 1].text.suffix(60_000))
            }
        } else {
            appendTerminalLine(text, kind: .output, to: terminalID)
        }
    }

    private func applyTerminalOutput(_ text: String, to index: Int) {
        var screen = terminals[index].screen
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            switch scalar.value {
            case 8, 127:
                if screen.cursorColumn > 0 {
                    screen.cursorColumn -= 1
                    replaceCharacter(in: &screen, at: screen.cursorColumn, with: " ")
                }
            case 10:
                screen.cursorRow += 1
                screen.cursorColumn = 0
                ensureScreenRow(&screen)
            case 13:
                screen.cursorColumn = 0
            case 9:
                let spaces = 4 - (screen.cursorColumn % 4)
                for _ in 0..<spaces { insertPrintable(" ", into: &screen) }
            case 27:
                handleEscapeSequence(iterator: &iterator, screen: &screen)
            default:
                if scalar.value >= 32 {
                    insertPrintable(String(scalar), into: &screen)
                }
            }
        }
        if screen.lines.count > 500 {
            let removed = screen.lines.count - 500
            screen.lines.removeFirst(removed)
            screen.cursorRow = max(0, screen.cursorRow - removed)
        }
        terminals[index].screen = screen
    }

    private func handleEscapeSequence(iterator: inout String.UnicodeScalarView.Iterator, screen: inout TerminalScreen) {
        guard let next = iterator.next(), next == "[" else { return }
        var parameters = ""
        while let scalar = iterator.next() {
            if scalar.value >= 0x40, scalar.value <= 0x7E {
                applyCSI(final: Character(scalar), parameters: parameters, screen: &screen)
                return
            }
            parameters.unicodeScalars.append(scalar)
        }
    }

    private func applyCSI(final: Character, parameters: String, screen: inout TerminalScreen) {
        let values = parameters.split(separator: ";").compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "?"))) }
        let amount = max(values.first ?? 1, 1)
        switch final {
        case "A":
            screen.cursorRow = max(0, screen.cursorRow - amount)
        case "B":
            screen.cursorRow += amount
            ensureScreenRow(&screen)
        case "C":
            screen.cursorColumn += amount
        case "D":
            screen.cursorColumn = max(0, screen.cursorColumn - amount)
        case "G":
            screen.cursorColumn = max(0, amount - 1)
        case "H", "f":
            screen.cursorRow = max(0, (values.first ?? 1) - 1)
            screen.cursorColumn = max(0, (values.dropFirst().first ?? 1) - 1)
            ensureScreenRow(&screen)
        case "J":
            if values.first ?? 0 == 2 {
                screen.lines = [""]
                screen.cursorRow = 0
                screen.cursorColumn = 0
            }
        case "K":
            ensureScreenRow(&screen)
            let line = screen.lines[screen.cursorRow]
            if screen.cursorColumn < line.count {
                screen.lines[screen.cursorRow] = String(line.prefix(screen.cursorColumn))
            }
        case "m":
            break
        default:
            break
        }
    }

    private func insertPrintable(_ text: String, into screen: inout TerminalScreen) {
        ensureScreenRow(&screen)
        padLine(&screen.lines[screen.cursorRow], to: screen.cursorColumn)
        var line = screen.lines[screen.cursorRow]
        let index = line.index(line.startIndex, offsetBy: screen.cursorColumn)
        if index < line.endIndex {
            line.replaceSubrange(index...index, with: text)
        } else {
            line.append(text)
        }
        screen.lines[screen.cursorRow] = line
        screen.cursorColumn += text.count
    }

    private func replaceCharacter(in screen: inout TerminalScreen, at column: Int, with text: String) {
        ensureScreenRow(&screen)
        padLine(&screen.lines[screen.cursorRow], to: column)
        var line = screen.lines[screen.cursorRow]
        let index = line.index(line.startIndex, offsetBy: column)
        if index < line.endIndex {
            line.replaceSubrange(index...index, with: text)
        }
        screen.lines[screen.cursorRow] = line
    }

    private func ensureScreenRow(_ screen: inout TerminalScreen) {
        while screen.cursorRow >= screen.lines.count {
            screen.lines.append("")
        }
    }

    private func padLine(_ line: inout String, to column: Int) {
        if line.count < column {
            line += String(repeating: " ", count: column - line.count)
        }
    }

    private func markTerminal(_ terminalID: WorkspaceTerminalSession.ID?, running: Bool) {
        guard let index = terminalIndex(for: terminalID) else { return }
        terminals[index].isRunning = running
    }

    private func terminalIndex(for terminalID: WorkspaceTerminalSession.ID?) -> Int? {
        if let terminalID, let index = terminals.firstIndex(where: { $0.id == terminalID }) { return index }
        return terminals.indices.first
    }

    private func importedSkillsRootURL() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("EasyChat", isDirectory: true)
            .appendingPathComponent("Skills", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func copySkillFolderToApplicationSupport(from sourceURL: URL) throws -> URL {
        let root = try importedSkillsRootURL()
        let safeName = sourceURL.lastPathComponent.replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
        let destination = root.appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination.standardizedFileURL
    }

    private func deleteImportedSkillFolderIfNeeded(_ skill: SkillConfig) {
        guard !skill.localFolderPath.isEmpty else { return }
        let url = URL(fileURLWithPath: skill.localFolderPath).standardizedFileURL
        guard (try? importedSkillsRootURL()).map({ url.path.hasPrefix($0.path + "/") }) == true else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func loadSkillFolder(from folderURL: URL, originalFolderName: String? = nil) throws -> SkillConfig {
        let skillURL = folderURL.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillURL.path) else {
            throw ChatError.builtinToolFailed("Skill 文件夹内必须包含 SKILL.md。")
        }

        let skillData = try Data(contentsOf: skillURL)
        guard let skillContent = textPreview(from: skillData), !skillContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.builtinToolFailed("SKILL.md 为空或不是文本。")
        }

        let files = try loadSkillFiles(in: folderURL, excluding: skillURL)
        let name = skillName(from: folderURL, content: skillContent)
        return SkillConfig(name: name, description: skillDescription(from: skillContent), content: skillContent, folderName: originalFolderName ?? folderURL.lastPathComponent, localFolderPath: folderURL.path, files: files, isEnabled: true)
    }

    private func loadSkillFiles(in folderURL: URL, excluding skillURL: URL) throws -> [SkillFile] {
        guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [SkillFile] = []
        for case let fileURL as URL in enumerator {
            if fileURL.standardizedFileURL == skillURL.standardizedFileURL { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 500_000, let text = textPreview(from: data) else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            files.append(SkillFile(relativePath: relativePath, content: text, byteCount: data.count))
        }
        return files
    }

    private func skillName(from folderURL: URL, content: String) -> String {
        if let heading = content.split(separator: "\n").map(String.init).first(where: { $0.hasPrefix("# ") }) {
            return String(heading.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return folderURL.lastPathComponent
    }

    private func skillDescription(from content: String) -> String {
        content.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? "Skill 文件夹"
    }

    private func resolvedSkill(for skillName: String?) -> SkillConfig? {
        let enabledSkills = settings.skills.filter(\.isEnabled)
        guard let skillName, !skillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return enabledSkills.count == 1 ? enabledSkills.first : nil
        }
        let normalized = skillName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return settings.skills.first { skill in
            skill.name.lowercased() == normalized
                || skill.folderName.lowercased() == normalized
                || skill.name.lowercased().contains(normalized)
                || normalized.contains(skill.name.lowercased())
        }
    }

    private func migrateImportedSkillsIfNeeded() {
        var changed = false
        for index in settings.skills.indices {
            guard settings.skills[index].isEnabled, !settings.skills[index].folderName.isEmpty else { continue }
            if !settings.skills[index].localFolderPath.isEmpty, FileManager.default.fileExists(atPath: settings.skills[index].localFolderPath) { continue }
            if let localURL = findImportedSkillFolder(for: settings.skills[index]) {
                settings.skills[index].localFolderPath = localURL.path
                changed = true
            }
        }
        if changed { persistSettings() }
    }

    private func findImportedSkillFolder(for skill: SkillConfig) -> URL? {
        guard let root = try? importedSkillsRootURL(), let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        let candidates = children.filter { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { return false }
            let skillURL = url.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillURL.path) else { return false }
            let nameMatch = !skill.folderName.isEmpty && url.lastPathComponent.lowercased().hasPrefix(skill.folderName.lowercased())
            let contentMatch: Bool = {
                guard let data = try? Data(contentsOf: skillURL), let text = textPreview(from: data) else { return false }
                return text == skill.content || text.contains(skill.name) || text.contains(skill.description)
            }()
            return nameMatch || contentMatch
        }
        return candidates.sorted { $0.lastPathComponent > $1.lastPathComponent }.first?.standardizedFileURL
    }

    private func restorePersistedSecurityScopes() {
        activeSecurityScopedURLs.removeAll()
        if let bookmarkData = settings.workspaceBookmark, let url = resolveBookmark(bookmarkData) {
            _ = url.startAccessingSecurityScopedResource()
            activeSecurityScopedURLs.append(url)
            settings.workspacePath = url.path
        }
        for bookmark in settings.authorizedBookmarks {
            if let url = resolveBookmark(bookmark.bookmarkData) {
                _ = url.startAccessingSecurityScopedResource()
                activeSecurityScopedURLs.append(url)
            }
        }
    }

    private func authorize(url: URL, saveAsWorkspace: Bool) {
        let standardizedURL = url.standardizedFileURL
        _ = standardizedURL.startAccessingSecurityScopedResource()
        activeSecurityScopedURLs.append(standardizedURL)
        do {
            let bookmarkData = try standardizedURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if saveAsWorkspace {
                settings.workspacePath = standardizedURL.path
                settings.workspaceBookmark = bookmarkData
            } else if !settings.authorizedBookmarks.contains(where: { $0.path == standardizedURL.path }) {
                settings.authorizedBookmarks.append(SecurityScopedBookmark(path: standardizedURL.path, bookmarkData: bookmarkData))
            }
        } catch {
            showAlert("授权保存失败：\(error.localizedDescription)")
        }
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        return url.standardizedFileURL
    }

    private func ensureAccessForTerminalCommand(_ commandLine: String) async {
        guard isRunningInAppSandbox else { return }
        let paths = terminalPathsNeedingAuthorization(in: commandLine)
        guard !paths.isEmpty else { return }
        let missingPaths = paths.filter { !isPathAuthorized($0) }
        guard !missingPaths.isEmpty else { return }
        appendTerminalLine("命令可能需要访问以下路径，请在弹出的授权面板中选择对应文件或上级文件夹：\n\(missingPaths.joined(separator: "\n"))", kind: .system, to: selectedTerminalID)
        requestAccessForPaths(missingPaths)
    }

    private func requestAccessForPaths(_ paths: [String]) {
        for path in compactAuthorizationTargets(paths) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "授权访问"
            panel.directoryURL = suggestedAuthorizationDirectory(for: path)
            panel.message = "请选择此命令需要访问的文件或上级文件夹：\n\(path)"
            if panel.runModal() == .OK, let url = panel.url {
                authorize(url: url, saveAsWorkspace: false)
            }
        }
        persistSettings()
    }

    private func terminalPathsNeedingAuthorization(in commandLine: String) -> [String] {
        let pattern = #"(?:'([^']+/[^']*)'|\"([^\"]+/[^\"]*)\"|(?<![\w.-])(/[^\s;&|><`]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(commandLine.startIndex..<commandLine.endIndex, in: commandLine)
        var paths: [String] = []
        for match in regex.matches(in: commandLine, range: nsRange) {
            for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
                guard let range = Range(match.range(at: index), in: commandLine) else { continue }
                var value = String(commandLine[range])
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                value = value.replacingOccurrences(of: "\\ ", with: " ")
                if value.hasPrefix("/"), !value.hasPrefix("/usr/"), !value.hasPrefix("/bin/"), !value.hasPrefix("/sbin/"), !value.hasPrefix("/opt/homebrew/") {
                    paths.append(value)
                }
            }
        }
        return Array(Set(paths)).sorted()
    }

    private func isPathAuthorized(_ path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if let workspacePath = workspaceURL?.path, standardizedPath == workspacePath || standardizedPath.hasPrefix(workspacePath + "/") { return true }
        return activeSecurityScopedURLs.contains { url in
            let authorizedPath = url.standardizedFileURL.path
            return standardizedPath == authorizedPath || standardizedPath.hasPrefix(authorizedPath + "/")
        }
    }

    private func compactAuthorizationTargets(_ paths: [String]) -> [String] {
        var targets: [String] = []
        for path in paths.sorted() {
            if targets.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
            targets.append(path)
        }
        return targets
    }

    private func suggestedAuthorizationDirectory(for path: String) -> URL? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url.deletingLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }

    private func persistConversations() {
        save(conversations, key: Self.conversationsKey)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

struct TerminalApprovalRequest: Identifiable {
    let id = UUID()
    let command: String
    let args: [String]
    let workingDirectory: String
    let completion: (Bool) -> Void

    var displayCommand: String {
        ([command] + args).map { value in
            value.contains(" ") ? "\"\(value)\"" : value
        }.joined(separator: " ")
    }

    func approve() { completion(true) }
    func deny() { completion(false) }
}
