import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: SettingsSection = .provider

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("模型、工具和技能工作台")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)

                ForEach(SettingsSection.allCases) { section in
                    SettingsNavItem(section: section, isSelected: section == selectedSection) {
                        selectedSection = section
                    }
                }

                Spacer()
                Button("完成") {
                    viewModel.persistSettings()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(18)
            }
            .frame(width: 220)
            .background(Color.white.opacity(0.74))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selectedSection.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignToken.ink)
                    selectedContent
                }
                .padding(28)
            }
        }
        .frame(width: 920, height: 720)
        .background(AppBackground())
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .provider:
            ProviderSettingsPanel(viewModel: viewModel)
        case .parameters:
            SettingsCard(title: "模型参数", subtitle: "统一管理采样、输出长度和推理强度。") {
                ParameterPanel(viewModel: viewModel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .localTools:
            SettingsCard(title: "内置工具", subtitle: "由 Easy Chat 执行搜索、网页抓取、文件读取、轻量 JS 和工作区终端编排。") {
                Toggle("启用内置工具", isOn: $viewModel.settings.enableBuiltinTools)
                    .onChange(of: viewModel.settings.enableBuiltinTools) { _, _ in viewModel.persistSettings() }
                Toggle("向 AI 暴露当前工作区路径", isOn: $viewModel.settings.exposeWorkspaceToAI)
                    .onChange(of: viewModel.settings.exposeWorkspaceToAI) { _, _ in viewModel.persistSettings() }
                Toggle("启用流式输出", isOn: $viewModel.settings.enableStreaming)
                    .onChange(of: viewModel.settings.enableStreaming) { _, _ in viewModel.persistSettings() }
                Toggle("YOLO 模式（跳过所有命令确认）", isOn: $viewModel.settings.yoloMode)
                    .onChange(of: viewModel.settings.yoloMode) { _, _ in viewModel.persistSettings() }
                if viewModel.settings.yoloMode {
                    Text("⚠️ YOLO 模式下 AI 的所有工具调用（包括终端命令和文件写入）将自动执行，不再弹出确认。请确保你信任当前模型。")
                        .font(.caption)
                        .foregroundStyle(DesignToken.rose)
                }
                Stepper("超时时间：\(viewModel.settings.builtinToolTimeout) 秒", value: $viewModel.settings.builtinToolTimeout, in: 3...120, step: 1)
                    .onChange(of: viewModel.settings.builtinToolTimeout) { _, _ in viewModel.persistSettings() }
                Stepper("连续工具调用轮数：\(viewModel.settings.maxToolRounds)", value: $viewModel.settings.maxToolRounds, in: 0...100, step: 1)
                    .onChange(of: viewModel.settings.maxToolRounds) { _, _ in viewModel.persistSettings() }
                Text("当 AI 回复中继续包含 {\"tool\": ...} 时，最多自动连续执行这么多轮。设为 0 可禁用自动工具循环。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Label("web_search：搜索网页并返回标题、摘要和链接", systemImage: "magnifyingglass")
                    Label("fetch_url：抓取 http/https 页面并抽取可读文本", systemImage: "safari")
                    Label("fetch_urls / url_to_markdown / extract_links：批量抓取、Markdown 化、提取链接", systemImage: "link")
                    Label("read_file / write_file / list_files：读取、写入和浏览用户授权范围内文件", systemImage: "folder")
                    Label("terminal / terminal_read：在工作区运行命令并读取终端内容", systemImage: "terminal")
                    Label("run_javascript：执行小段 JavaScript 表达式或脚本", systemImage: "curlybraces")
                    Label("github_trending：抓取 GitHub Trending daily/weekly/monthly", systemImage: "star")
                }
                .font(.callout)
                Text("模型会输出 {\"tool\": ...} 请求，App 截获后执行，再把结果回传给模型。terminal 会像 VS Code 终端一样实时显示输出，并在执行前请求用户批准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .mcp:
            MCPSettingsPanel(viewModel: viewModel)
        case .skills:
            SkillsSettingsPanel(viewModel: viewModel)
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case provider
    case parameters
    case localTools
    case mcp
    case skills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: "Provider & Models"
        case .parameters: "Model Parameters"
        case .localTools: "Built-in Tools"
        case .mcp: "MCP Servers"
        case .skills: "Skills"
        }
    }

    var icon: String {
        switch self {
        case .provider: "cloud"
        case .parameters: "dial.medium"
        case .localTools: "terminal"
        case .mcp: "server.rack"
        case .skills: "sparkles"
        }
    }
}

struct SettingsNavItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .frame(width: 22)
                Text(section.title)
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(isSelected ? DesignToken.blue : DesignToken.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(isSelected ? Color.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DesignToken.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(DesignToken.border))
        .shadow(color: DesignToken.shadow.opacity(0.75), radius: 18, y: 10)
    }
}

struct ProviderSettingsPanel: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        SettingsCard(title: "连接", subtitle: "兼容 OpenAI 格式的 API 提供商。") {
            TextField("Base URL", text: $viewModel.settings.baseURL).textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $viewModel.settings.apiKey).textFieldStyle(.roundedBorder)
            HStack {
                Toggle("默认使用 v1/responses", isOn: $viewModel.settings.useResponsesAPI)
                Spacer()
                Button(viewModel.isFetchingModels ? "拉取中…" : "拉取模型") {
                    Task { await viewModel.fetchModels() }
                }
                .disabled(viewModel.isFetchingModels)
            }
        }

        SettingsCard(title: "模型", subtitle: "对话模型仍可在输入框内快速切换。") {
            Picker("聊天模型", selection: $viewModel.settings.chatModel) {
                ForEach(viewModel.settings.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            TextField("绘图模型", text: $viewModel.settings.imageModel).textFieldStyle(.roundedBorder)
        }

        SettingsCard(title: "端点路径", subtitle: "适配第三方兼容提供商。") {
            TextField("模型列表路径", text: $viewModel.settings.modelsPath).textFieldStyle(.roundedBorder)
            TextField("Responses 路径", text: $viewModel.settings.responsesPath).textFieldStyle(.roundedBorder)
            TextField("Chat Completions 路径", text: $viewModel.settings.chatCompletionsPath).textFieldStyle(.roundedBorder)
            TextField("图片生成路径", text: $viewModel.settings.imageGenerationsPath).textFieldStyle(.roundedBorder)
        }
    }
}

struct MCPSettingsPanel: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        SettingsCard(title: "MCP 模式", subtitle: "按 VS Code Copilot Chat 的思路：Server 注册、工具发现、调用前确认、结果回填。") {
            Toggle("启用 MCP", isOn: $viewModel.settings.enableMCP)
                .onChange(of: viewModel.settings.enableMCP) { _, _ in viewModel.persistSettings() }
            Picker("模式", selection: $viewModel.settings.mcpMode) {
                ForEach(MCPMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.settings.mcpMode) { _, _ in viewModel.persistSettings() }
            Text("自动：使用所有 active Server；手动：仅使用 selected Server。每个 Server 会映射为 mcp_<name> 工具入口；未开启自动批准时，调用前会显示确认面板。")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label("工具发现：后续接入 tools/list 后可把 MCP Tool 展示为独立工具", systemImage: "square.stack.3d.up")
                Label("调用交互：复用终端确认面板，显示 server、tool 和 JSON input", systemImage: "checkmark.shield")
                Label("结果展示：按 ChatToolInvocationPart 风格展示 input/output/isConfirmed/isComplete", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        SettingsCard(title: "Servers", subtitle: "支持 Streamable HTTP / SSE / stdio 基础配置。") {
            HStack {
                Button { viewModel.addMCPServer() } label: { Label("添加 Server", systemImage: "plus") }
                Spacer()
                Text("\(viewModel.settings.mcpServers.filter { $0.isActive }.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($viewModel.settings.mcpServers) { $server in
                MCPServerRow(server: $server) {
                    viewModel.deleteMCPServer(server)
                }
                .onChange(of: server) { _, _ in viewModel.persistSettings() }
            }
        }
    }
}

struct MCPServerRow: View {
    @Binding var server: MCPServerConfig
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("", isOn: $server.isActive).labelsHidden()
                TextField("名称", text: $server.name)
                    .font(.headline)
                Picker("类型", selection: $server.type) {
                    ForEach(MCPServerType.allCases) { type in Text(type.title).tag(type) }
                }
                .frame(width: 160)
                Toggle("选择", isOn: $server.isSelected)
                Toggle("自动批准", isOn: $server.autoApprove)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            TextField("描述", text: $server.description).textFieldStyle(.roundedBorder)
            if server.type == .stdio {
                TextField("Command", text: $server.command).textFieldStyle(.roundedBorder)
                TextField("Args", text: $server.args).textFieldStyle(.roundedBorder)
            } else {
                TextField("URL", text: $server.url).textFieldStyle(.roundedBorder)
                TextField("Headers JSON / key-value", text: $server.headers).textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .background(Color(red: 0.97, green: 0.985, blue: 1.0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignToken.border))
    }
}

struct SkillsSettingsPanel: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var isShowingSkillFolderImporter = false

    var body: some View {
        SettingsCard(title: "Skills", subtitle: "一个 Skill 推荐是包含 SKILL.md 和附带文件的文件夹；SKILL.md 作为入口说明，其他文本文件作为参考资料注入。") {
            HStack {
                Toggle("启用 Skills", isOn: $viewModel.settings.enableSkills)
                    .onChange(of: viewModel.settings.enableSkills) { _, _ in viewModel.persistSettings() }
                Spacer()
                Button { isShowingSkillFolderImporter = true } label: { Label("导入 Skill 文件夹", systemImage: "folder.badge.plus") }
                Button { viewModel.addSkill() } label: { Label("添加纯文本 Skill", systemImage: "plus") }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Skills 会作为可按需加载的提示词清单提供给模型。模型判断任务适合某个 Skill 时，会先调用 load_skill 读取完整 SKILL.md 和需要的附带文件，再继续回答。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("提示词预览长度：\(viewModel.settings.skillCatalogPreviewCharacters) 字符", value: $viewModel.settings.skillCatalogPreviewCharacters, in: 120...2_000, step: 120)
                    .onChange(of: viewModel.settings.skillCatalogPreviewCharacters) { _, _ in viewModel.persistSettings() }
            }
            .padding(12)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
            Text("文件夹内必须包含 SKILL.md。附带文件不限制数量；单文件 500KB 以内的文本内容会被读取。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach($viewModel.settings.skills) { $skill in
                SkillRow(skill: $skill, viewModel: viewModel) {
                    viewModel.deleteSkill(skill)
                }
                .onChange(of: skill) { _, _ in viewModel.persistSettings() }
            }
            DisclosureGroup("兼容旧版纯文本 Skills") {
                TextEditor(text: $viewModel.settings.skillsText)
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignToken.border))
                    .onChange(of: viewModel.settings.skillsText) { _, _ in viewModel.persistSettings() }
            }
        }
        .fileImporter(isPresented: $isShowingSkillFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                viewModel.importSkillFolder(from: url)
            }
        }
    }
}

struct SkillRow: View {
    @Binding var skill: SkillConfig
    @ObservedObject var viewModel: ChatViewModel
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("", isOn: $skill.isEnabled).labelsHidden()
                TextField("Skill 名称", text: $skill.name)
                    .font(.headline)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            TextField("描述", text: $skill.description).textFieldStyle(.roundedBorder)
            if !skill.folderName.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Label(skill.folderName, systemImage: "folder")
                        Text("SKILL.md + \(skill.files.count) 个附带文件")
                            .foregroundStyle(.secondary)
                    }
                    if !skill.localFolderPath.isEmpty {
                        Text("本地副本：\(skill.localFolderPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignToken.border))
            }
            TextEditor(text: $skill.content)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignToken.border))
            if !skill.files.isEmpty {
                DisclosureGroup("附带文件（\(skill.files.count)）") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(skill.files) { file in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(DesignToken.blue)
                                Text(file.relativePath)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.99, green: 0.98, blue: 0.95), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignToken.border))
    }
}
