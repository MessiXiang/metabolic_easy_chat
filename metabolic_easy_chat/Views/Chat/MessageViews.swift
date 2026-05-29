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
                                onExportConversation: { viewModel.exportSelectedConversation() },
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
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(DesignToken.blue)
                Text("编辑消息")
                    .font(.caption.bold())
                Spacer()
                Button {
                    editorFocused = false
                    viewModel.cancelEditing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .help("取消编辑")
                .keyboardShortcut(.escape, modifiers: [])
            }
            TextEditor(text: $viewModel.editingText)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
                .focused($editorFocused)
                .onAppear {
                    editorFocused = true
                }
            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    editorFocused = false
                    viewModel.cancelEditing()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button("保存并重新生成") { Task { await viewModel.submitEdit() } }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignToken.blue)
                    .disabled(viewModel.editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.00), Color(red: 0.96, green: 0.99, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(DesignToken.blue.opacity(0.40)))
        .shadow(color: DesignToken.shadow, radius: 18, y: 10)
        .padding(.horizontal, 24)
        .onExitCommand {
            editorFocused = false
            viewModel.cancelEditing()
        }
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
    let onExportConversation: () -> Void
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
            Button("导出当前对话…") { onExportConversation() }
            Divider()
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
          