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
    @Published var collapsedWorkspaceFolders: Set<String> = []
    @Published var selectedWorkspaceFile: WorkspaceFileItem?
    @Published var selectedWorkspaceFilePreview = ""
    @Published var terminals: [WorkspaceTerminalSession] = []
    @Published var selectedTerminalID: WorkspaceTerminalSession.ID?
    @Published var editingMessageID: ChatMessage.ID?
    @Published var editingText = ""
    @Published var streamingText = ""
    @Published var isMetabolismWorking = false

    private var activeSecurityScopedURLs: [URL] = []
    private let terminalService = WorkspaceTerminalService()
    private var terminalProcesses: [WorkspaceTerminalSession.ID: Process] = [:]
    private var terminalInputHandles: [WorkspaceTerminalSession.ID: FileHandle] = [:]
    private var activeResponseTask: Task<Void, Never>?
    private var streamingFlushTask: Task<Void, Never>?
    private var pendingStreamingDelta = ""
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

    var isMetabolismModeActive: Bool {
        settings.metabolismSession != nil
    }

    var metabolismSession: MetabolismSession? {
        settings.metabolismSession
    }

    var visibleWorkspaceFiles: [WorkspaceFileItem] {
        workspaceFiles.filter { item in
            !collapsedWorkspaceFolders.contains { folder in
                item.relativePath != folder && item.relativePath.hasPrefix(folder + "/")
            }
        }
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
        for _ in message.images {
            count += 85
        }
        return max(count, 1)
    }

    func emergencyStopResponse() {
        shouldStopResponse = true
        activeResponseTask?.cancel()
        activeResponseTask = nil
        commitStreamingDisplayAsStoppedMessage()
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
        guard !isMetabolismModeActive else {
            showAlert("新陈代谢模式中禁止切换工作区。请先点击“回到原工作区”。")
            return
        }
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

    func startMetabolismMode() async {
        guard !isMetabolismWorking else { return }
        isMetabolismWorking = true
        defer { isMetabolismWorking = false }

        let repositoryURL = "https://github.com/MessiXiang/metabolic_easy_chat"
        let originalWorkspacePath = settings.workspacePath
        let originalWorkspaceBookmark = settings.workspaceBookmark
        let environment = terminalEnvironment()
        let fallbackUser = NSUserName().replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()

        let setupTerminalID = createTerminal(title: "gh setup", command: "/bin/zsh", args: ["-lc", "gh --version || brew install gh"], workingDirectory: workspaceURL, environment: environment, startImmediately: false)
        appendTerminalLine("正在检测 GitHub CLI：gh --version", kind: .system, to: setupTerminalID)
        var ghVersionResult = await runProcess(command: "/usr/bin/env", args: ["zsh", "-lc", "gh --version"], workingDirectory: workspaceURL, environment: environment, timeout: 12, terminalID: setupTerminalID) { _ in }
        if ghVersionResult.status != .completed {
            appendTerminalLine("未检测到 gh，正在自动运行：brew install gh", kind: .system, to: setupTerminalID)
            let installResult = await runProcess(command: "/usr/bin/env", args: ["zsh", "-lc", "brew install gh"], workingDirectory: workspaceURL, environment: environment, timeout: 600, terminalID: setupTerminalID) { _ in }
            guard installResult.status == .completed else {
                showAlert("未检测到 gh，且自动执行 brew install gh 失败。请查看终端输出后重试。")
                return
            }
            ghVersionResult = await runProcess(command: "/usr/bin/env", args: ["zsh", "-lc", "gh --version"], workingDirectory: workspaceURL, environment: environment, timeout: 12, terminalID: setupTerminalID) { _ in }
            guard ghVersionResult.status == .completed else {
                showAlert("gh 安装后仍无法运行 gh --version，请查看终端输出后重试。")
                return
            }
        }

        let githubToken = settings.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !githubToken.isEmpty else {
            showAlert("请先在设置中填写 GitHub Personal Access Token。\n获取链接：https://github.com/settings/tokens")
            return
        }

        appendTerminalLine("正在使用设置中的 GitHub Token 登录 gh，并检查仓库访问权限。", kind: .system, to: setupTerminalID)
        let loginCommand = "printf %s \(shellQuote(githubToken)) | gh auth login -h github.com --with-token >/dev/null 2>&1 || true; gh auth status -h github.com && gh api user --jq .login && gh api repos/MessiXiang/metabolic_easy_chat >/dev/null"
        let authResult = await runProcess(command: "/usr/bin/env", args: ["zsh", "-lc", loginCommand], workingDirectory: workspaceURL, environment: environment, timeout: 60, terminalID: setupTerminalID) { _ in }
        let authLines = authResult.output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let ghUser = authLines.last ?? ""
        guard authResult.status == .completed && !ghUser.isEmpty else {
            showAlert("GitHub CLI 登录或权限检查失败。请确认设置中的 Token 有访问仓库和创建 PR 所需权限（建议 repo 权限）。\n获取链接：https://github.com/settings/tokens")
            return
        }
        let isGitHubReady = true

        let branchName = "\(ghUser)_\(random)"

        do {
            let cloneURL = try metabolismCloneDestination(branchName: branchName)
            if FileManager.default.fileExists(atPath: cloneURL.path) {
                try FileManager.default.removeItem(at: cloneURL)
            }
            let parentURL = cloneURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

            let cloneCommand = "git clone \(shellQuote(repositoryURL)) \(shellQuote(cloneURL.path)) && cd \(shellQuote(cloneURL.path)) && git checkout main && git checkout -b \(shellQuote(branchName))"
            let terminalID = createTerminal(title: "metabolism", command: "/bin/zsh", args: ["-lc", cloneCommand], workingDirectory: parentURL, environment: environment, startImmediately: false)
            appendTerminalLine("启动 EasyChat 新陈代谢：克隆仓库并创建分支 \(branchName)", kind: .system, to: terminalID)
            let cloneResult = await runProcess(command: "/bin/zsh", args: ["-lc", cloneCommand], work