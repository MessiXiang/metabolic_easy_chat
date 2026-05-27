import SwiftUI
import AppKit

struct MessageListView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if let conversation = viewModel.selectedConversation, conversation.messages.isEmpty {
                        EmptyChatView()
                            .padding(.top, 80)
                    }

                    ForEach(viewModel.selectedConversation?.messages ?? []) { message in
                        if viewModel.editingMessageID == message.id {
                            MessageEditView(viewModel: viewModel)
                                .id(message.id)
                        } else if message.isToolResult {
                            // Tool result messages are hidden — they're internal
                            EmptyView().id(message.id)
                        } else if message.isIntermediateResponse {
                            CollapsedIntermediateBubble(message: message)
                                .id(message.id)
                        } else {
                            MessageBubble(
                                message: message,
                                onDelete: { viewModel.deleteMessage(message) },
                                onRegenerate: {
                                    Task { await viewModel.regenerate(from: message) }
                                },
                                onEdit: { viewModel.startEditingMessage(message) },
                                onApplyDiff: { diff in viewModel.applyDiff(diff, in: message.id) },
                                onRevertDiff: { diff in viewModel.revertDiff(diff, in: message.id) }
                            )
                                .id(message.id)
                        }
                    }

                    if viewModel.isSending {
                        if viewModel.streamingText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                            StreamingToolIndicator()
                        } else {
                            StreamingBubbleView(streamingText: viewModel.streamingText, composerMode: viewModel.composerMode)
                        }
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .background(.clear)
            .onChange(of: viewModel.selectedConversation?.messages.count ?? 0) { _, _ in
                if let last = viewModel.selectedConversation?.messages.last {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingText) { _, newValue in
                // Only scroll every ~300 chars to avoid per-token animation overhead
                if newValue.count % 40 < 4 || newValue.hasSuffix("\n") {
                    proxy.scrollTo("streaming-bottom", anchor: .bottom)
                }
            }
        }
    }
}

struct StreamingToolIndicator: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape.2")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(pulse ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: pulse)
            Text("正在调用工具…")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.06), in: Capsule())
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("streaming-bottom")
        .onAppear { pulse = true }
    }
}

struct StreamingBubbleView: View {
    let streamingText: String
    let composerMode: ComposerMode
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text("AI")
                        .font(.caption.bold())
                    Text(composerMode == .image ? "正在生成图片…" : "正在回复…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                }
                if !streamingText.isEmpty {
                    MarkdownMessageText(streamingText, isStreaming: true)
                } else {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(DesignToken.blue.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .scaleEffect(pulse ? 1.0 : 0.5)
                                .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15), value: pulse)
                        }
                    }
                    .onAppear { pulse = true }
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(DesignToken.border.opacity(0.6)))
            .shadow(color: DesignToken.shadow.opacity(0.5), radius: 16, y: 8)
            .frame(maxWidth: 760, alignment: .leading)
            Spacer(minLength: 120)
        }
        .padding(.horizontal, 24)
        .id("streaming-bottom")
    }
}

struct CollapsedIntermediateBubble: View {
    let message: ChatMessage
    @State private var isExpanded = false

    private static let toolService = ToolInvocationService(settings: ProviderSettings())

    private var toolNames: [String] {
        Self.toolService.extractInvocations(from: message.text).map(\.name)
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("调用了 \(toolNames.count) 个工具")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        if !message.toolInvocations.isEmpty {
                            Text("· \(message.toolInvocations.filter(\.isComplete).count)/\(message.toolInvocations.count) 完成")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.toolInvocations) { record in
                            HStack(spacing: 6) {
                                Image(systemName: record.isComplete ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9))
                                    .foregroundStyle(record.status == .completed ? DesignToken.mint : (record.status == .failed ? DesignToken.rose : .secondary))
                                Text(record.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(DesignToken.ink)
                                Text(record.input.prefix(60) + (record.input.count > 60 ? "…" : ""))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        if !Self.toolService.displayTextByHidingInvocations(in: message.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(Self.toolService.displayTextByHidingInvocations(in: message.text))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
            .padding(.vertical, 4)
            Spacer(minLength: 200)
        }
        .padding(.horizontal, 24)
    }
}

struct MessageEditView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(DesignToken.blue)
                Text("编辑消息")
                    .font(.caption.bold())
                Spacer()
            }
            TextEditor(text: $viewModel.editingText)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
            HStack {
                Spacer()
                Button("取消") { viewModel.cancelEditing() }
                Button("保存并重新生成") { Task { await viewModel.submitEdit() } }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignToken.blue)
                    .disabled(viewModel.editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.00), Color(red: 0.96, green: 0.99, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(DesignToken.blue.opacity(0.40)))
        .shadow(color: DesignToken.shadow, radius: 18, y: 10)
        .padding(.horizontal, 24)
    }
}

struct EmptyChatView: View {
    @State private var appear = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [DesignToken.blue.opacity(0.08), DesignToken.cyan.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(appear ? 1.0 : 0.8)
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [DesignToken.blue, DesignToken.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .scaleEffect(appear ? 1.0 : 0.6)
                    .opacity(appear ? 1.0 : 0.0)
            }

            VStack(spacing: 8) {
                Text("开始对话")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignToken.ink)
                Text("支持 OpenAI 兼容接口 · 图片生成 · 工具调用 · 工作区终端")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .opacity(appear ? 1.0 : 0.0)
            .offset(y: appear ? 0 : 12)

            HStack(spacing: 10) {
                FeatureTile(icon: "switch.2", title: "多模型")
                FeatureTile(icon: "brain.head.profile", title: "思考")
                FeatureTile(icon: "globe", title: "搜索")
                FeatureTile(icon: "photo", title: "图片")
                FeatureTile(icon: "terminal", title: "终端")
            }
            .opacity(appear ? 1.0 : 0.0)
            .offset(y: appear ? 0 : 16)
        }
        .padding(40)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color.white.opacity(0.5), lineWidth: 1))
        .shadow(color: DesignToken.shadow.opacity(0.5), radius: 30, y: 16)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) {
                appear = true
            }
        }
    }
}

struct FeatureTile: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(DesignToken.blue)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DesignToken.ink)
        }
        .frame(width: 72, height: 56)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.5), lineWidth: 0.5))
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let onDelete: () -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    let onApplyDiff: (FileDiffHunk) -> Void
    let onRevertDiff: (FileDiffHunk) -> Void
    @State private var appeared = false

    private static let toolService = ToolInvocationService(settings: ProviderSettings())

    private var toolRequests: [ToolInvocation] {
        guard message.role == .assistant else { return [] }
        return Self.toolService.extractInvocations(from: message.text)
    }

    private var displayText: String {
        guard message.role == .assistant else { return message.text }
        return Self.toolService.displayTextByHidingInvocations(in: message.text)
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 120) }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: message.role.icon)
                            .foregroundStyle(message.role == .user ? .blue : .purple)
                        Text(message.role.title)
                            .font(.caption.bold())
                        Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    MessageActionBar(message: message, onCopy: copyMessage, onDelete: onDelete, onRegenerate: onRegenerate, onEdit: onEdit)
                }

                if !displayText.isEmpty {
                    MarkdownMessageText(displayText)
                }

                if !toolRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(toolRequests) { request in
                            ToolRequestBubble(invocation: request)
                        }
                    }
                }

                ForEach(message.images) { image in
                    ImageBubble(image: image)
                }

                if !message.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(message.attachments) { attachment in
                            AttachmentChip(attachment: attachment, onRemove: nil)
                        }
                    }
                }

                if !message.diffs.isEmpty {
                    DiffPreviewView(diffs: message.diffs, messageID: message.id, onApply: onApplyDiff, onRevert: onRevertDiff)
                }

                if !message.toolInvocations.isEmpty {
                    ToolInvocationsView(records: message.toolInvocations)
                } else if !message.toolRuns.isEmpty {
                    ToolRunsView(toolRuns: message.toolRuns)
                }
            }
            .padding(18)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(message.role == .user ? DesignToken.blue.opacity(0.30) : DesignToken.border))
            .shadow(color: DesignToken.shadow, radius: 18, y: 10)
            .frame(maxWidth: 760, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user { Spacer(minLength: 120) }
        }
        .padding(.horizontal, 24)
        .contextMenu {
            Button("编辑") { onEdit() }
            Button("重新生成") { onRegenerate() }
            Button("删除", role: .destructive) { onDelete() }
        }
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.92, green: 0.96, blue: 1.00), Color(red: 0.96, green: 0.98, blue: 1.00)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(Color.white.opacity(0.85))
    }

    private func copyMessage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.copyText, forType: .string)
    }
}

struct ImageBubble: View {
    let image: ChatImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nsImage = image.nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignToken.border))
                    .frame(maxHeight: 420)
                    .shadow(color: DesignToken.shadow, radius: 16, y: 8)
                    .contextMenu {
                        Button("复制图片") { copyImage(nsImage) }
                        Button("保存图片…") { saveImage(nsImage) }
                    }
            }
            if let sourceURL = image.sourceURL {
                Text(sourceURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private func copyImage(_ nsImage: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
    }

    private func saveImage(_ nsImage: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = image.sourceURL ?? "image.png"
        if panel.runModal() == .OK, let url = panel.url {
            guard let tiffData = nsImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiffData),
                  let pngData = rep.representation(using: .png, properties: [:]) else { return }
            try? pngData.write(to: url)
        }
    }
}

struct DiffPreviewView: View {
    let diffs: [FileDiffHunk]
    let messageID: ChatMessage.ID
    let onApply: (FileDiffHunk) -> Void
    let onRevert: (FileDiffHunk) -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(diffs) { diff in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: diff.isApplied ? "checkmark.circle.fill" : "doc.badge.gearshape")
                                .foregroundStyle(diff.isApplied ? DesignToken.mint : DesignToken.orange)
                            Text(diff.filePath)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if diff.isApplied {
                                Button("回滚") { onRevert(diff) }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(DesignToken.rose)
                            } else {
                                Button("应用") { onApply(diff) }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        SimpleDiffView(oldContent: diff.oldContent, newContent: diff.newContent)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignToken.border))
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape")
                    .foregroundStyle(DesignToken.orange)
                Text("文件变更 \(diffs.filter(\.isApplied).count)/\(diffs.count) 已应用")
                    .font(.caption.weight(.bold))
                Spacer()
            }
            .padding(10)
            .background(DesignToken.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct SimpleDiffView: View {
    let oldContent: String
    let newContent: String

    var body: some View {
        let diffLines = computeDiffLines()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.prefix(60).enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(line.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(line.background)
                }
                if diffLines.count > 60 {
                    Text("… 省略 \(diffLines.count - 60) 行")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private struct DiffLine {
        let text: String
        let color: Color
        let background: Color
    }

    private func computeDiffLines() -> [DiffLine] {
        let oldLines = oldContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [DiffLine] = []
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)
        for line in oldLines where !newSet.contains(line) {
            result.append(DiffLine(text: "- \(line)", color: DesignToken.rose, background: DesignToken.rose.opacity(0.08)))
        }
        for line in newLines where !oldSet.contains(line) {
            result.append(DiffLine(text: "+ \(line)", color: Color(red: 0.1, green: 0.6, blue: 0.3), background: Color.green.opacity(0.08)))
        }
        if result.isEmpty {
            result.append(DiffLine(text: "（无差异或差异过复杂，请对比原文件）", color: .secondary, background: .clear))
        }
        return result
    }
}

private extension ChatMessage {
    var copyText: String {
        var sections: [String] = []
        if !text.isEmpty { sections.append(text) }
        if !images.isEmpty {
            let imageText = images.enumerated().map { index, image in
                "图片 \(index + 1)：\(image.sourceURL ?? image.mimeType)"
            }.joined(separator: "\n")
            sections.append(imageText)
        }
        if !attachments.isEmpty {
            let attachmentText = attachments.map { attachment in
                "附件：\(attachment.name)\n类型：\(attachment.mimeType)\n大小：\(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))\(attachment.textPreview.map { "\n文本预览：\n\($0)" } ?? "")"
            }.joined(separator: "\n\n")
            sections.append(attachmentText)
        }
        if !toolRuns.isEmpty {
            let toolText = toolRuns.map { run in
                "工具：\(run.title)\n状态：\(run.status.rawValue)\n\(run.output)"
            }.joined(separator: "\n\n")
            sections.append(toolText)
        }
        return sections.joined(separator: "\n\n---\n\n")
    }
}

struct ToolRequestBubble: View {
    let invocation: ToolInvocation

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
            Text(displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DesignToken.muted)
            Text(summary.prefix(50) + (summary.count > 50 ? "…" : ""))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(iconColor.opacity(0.05), in: Capsule())
    }

    private static let toolService = ToolInvocationService(settings: ProviderSettings())

    private var displayName: String {
        Self.toolService.definition(named: invocation.name)?.displayName ?? invocation.name
    }

    private var summary: String {
        let input = invocation.input
        switch invocation.name {
        case "read_file", "view", "write_file", "create_file", "create", "replace_string", "insert":
            return input.path ?? ""
        case "terminal":
            return ([input.command].compactMap { $0 } + (input.args ?? [])).joined(separator: " ")
        case "web_search", "think", "report_progress", "task_complete":
            return input.query ?? input.content ?? ""
        case "fetch_url", "url_to_markdown", "extract_links":
            return input.url ?? ""
        case "fetch_urls":
            return "\(input.urls?.count ?? 0) 个 URL"
        case "glob", "grep":
            return input.pattern ?? input.query ?? ""
        case "load_skill":
            return input.skill ?? ""
        default:
            return invocation.rawJSON
        }
    }

    private var iconName: String {
        switch invocation.name {
        case "terminal": "terminal"
        case "read_file", "view", "write_file", "create_file", "create", "replace_string", "insert": "doc.text"
        case "web_search", "fetch_url", "fetch_urls", "url_to_markdown", "extract_links": "globe"
        case "load_skill": "sparkles"
        default: "wrench.and.screwdriver"
        }
    }

    private var iconColor: Color {
        switch invocation.name {
        case "terminal": DesignToken.orange
        case "web_search", "fetch_url", "fetch_urls", "url_to_markdown", "extract_links": DesignToken.cyan
        case "load_skill": DesignToken.lilac
        default: DesignToken.blue
        }
    }
}

