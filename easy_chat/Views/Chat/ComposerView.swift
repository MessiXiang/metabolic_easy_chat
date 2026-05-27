import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @ObservedObject var viewModel: ChatViewModel
    var inputFocused: FocusState<Bool>.Binding
    @State private var editorHeight: CGFloat = 92
    @State private var isShowingFileImporter = false

    var body: some View {
        VStack(spacing: 10) {
            if !viewModel.pendingImages.isEmpty || !viewModel.pendingAttachments.isEmpty {
                PendingAttachmentsView(viewModel: viewModel)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(spacing: 0) {
                    ResizablePromptEditor(text: $viewModel.inputText, inputFocused: inputFocused, height: $editorHeight)
                    Divider()
                        .padding(.horizontal, 14)
                    composerToolbar
                }
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(DesignToken.border.opacity(0.6)))
                .shadow(color: DesignToken.shadow.opacity(0.6), radius: 14, y: 6)

                Button {
                    if viewModel.isSending {
                        viewModel.emergencyStopResponse()
                    } else {
                        Task { await viewModel.send() }
                    }
                } label: {
                    Image(systemName: viewModel.isSending ? "stop.fill" : (viewModel.composerMode == .image ? "paintbrush.pointed.fill" : "paperplane.fill"))
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: viewModel.isSending ? [DesignToken.rose, DesignToken.orange] : (viewModel.composerMode == .image ? [DesignToken.lilac, DesignToken.rose] : [DesignToken.blue, DesignToken.cyan]), startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: (viewModel.isSending ? DesignToken.rose : (viewModel.composerMode == .image ? DesignToken.lilac : DesignToken.blue)).opacity(0.22), radius: 12, y: 6)
                        .scaleEffect(viewModel.isSending ? 0.95 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isSending)
                }
                .buttonStyle(.plain)
                .help(viewModel.isSending ? "急停 AI 响应" : "发送")
                .disabled(!viewModel.isSending && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.pendingImages.isEmpty && viewModel.pendingAttachments.isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.white.opacity(0.88), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
            LinearGradient(colors: [DesignToken.blue.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result {
                urls.forEach { viewModel.addFileAttachment(from: $0) }
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in viewModel.handleDroppedFiles([url]) }
                }
            }
            return true
        }
    }

    private var composerToolbar: some View {
        HStack(spacing: 4) {
            // Attach
            ToolbarPillButton(icon: "paperclip", isActive: false) {
                isShowingFileImporter = true
            }
            .help("添加附件")

            Divider().frame(height: 16).padding(.horizontal, 2)

            // Model picker
            Menu {
                ForEach(viewModel.settings.availableModels, id: \.self) { model in
                    Button(model) { viewModel.settings.chatModel = model; viewModel.persistSettings() }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text(viewModel.settings.chatModel.split(separator: "/").last.map(String.init) ?? viewModel.settings.chatModel)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Divider().frame(height: 16).padding(.horizontal, 2)

            // Mode toggle
            ToolbarPillButton(icon: viewModel.composerMode == .image ? "photo.artframe" : "text.bubble", isActive: viewModel.composerMode == .image) {
                viewModel.composerMode = viewModel.composerMode == .chat ? .image : .chat
            }
            .help(viewModel.composerMode == .image ? "图片模式" : "对话模式")

            // API toggle
            ToolbarPillButton(icon: "bolt", isActive: viewModel.settings.useResponsesAPI) {
                viewModel.settings.useResponsesAPI.toggle(); viewModel.persistSettings()
            }
            .help(viewModel.settings.useResponsesAPI ? "Responses API" : "Chat Completions")

            // Reasoning
            ToolbarPillButton(icon: "brain.head.profile", isActive: viewModel.settings.enableReasoning) {
                viewModel.settings.enableReasoning.toggle(); viewModel.persistSettings()
            }
            .help(viewModel.settings.enableReasoning ? "思考已开启" : "思考已关闭")

            // Streaming
            ToolbarPillButton(icon: "water.waves", isActive: viewModel.settings.enableStreaming) {
                viewModel.settings.enableStreaming.toggle(); viewModel.persistSettings()
            }
            .help(viewModel.settings.enableStreaming ? "流式已开启" : "流式已关闭")

            // YOLO
            ToolbarPillButton(icon: "bolt.shield", isActive: viewModel.settings.yoloMode, activeColor: DesignToken.rose) {
                viewModel.settings.yoloMode.toggle(); viewModel.persistSettings()
            }
            .help(viewModel.settings.yoloMode ? "YOLO：跳过审核" : "安全模式")

            if viewModel.settings.enableReasoning {
                Menu {
                    ForEach(["minimal", "low", "medium", "high"], id: \.self) { value in
                        Button(value) { viewModel.settings.reasoningEffort = value; viewModel.persistSettings() }
                    }
                } label: {
                    Text(viewModel.settings.reasoningEffort)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if viewModel.composerMode == .image {
                Menu {
                    ForEach(["1024x1024", "1024x1536", "1536x1024"], id: \.self) { size in
                        Button(size) { viewModel.imageSize = size }
                    }
                } label: {
                    Text(viewModel.imageSize)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.pink.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            Text("⌘↩")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(.tertiary)

            ToolbarPillButton(icon: "arrow.clockwise", isActive: false) {
                Task { await viewModel.regenerateLastAssistant() }
            }
            .disabled(viewModel.isSending)
            .help("重新生成上一条")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct ToolbarPillButton: View {
    let icon: String
    let isActive: Bool
    var activeColor: Color = DesignToken.blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isActive ? activeColor : .secondary)
                .frame(width: 26, height: 26)
                .background(isActive ? activeColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PendingAttachmentsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.pendingImages) { image in
                    HStack(spacing: 8) {
                        if let nsImage = image.nsImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "photo")
                                .frame(width: 42, height: 42)
                        }
                        Text(image.sourceURL ?? "图片")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Button {
                            viewModel.removePendingImage(image)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
                }

                ForEach(viewModel.pendingAttachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        viewModel.removePendingAttachment(attachment)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct AttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .foregroundStyle(DesignToken.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(attachment.mimeType) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
    }
}

struct ResizablePromptEditor: View {
    @Binding var text: String
    var inputFocused: FocusState<Bool>.Binding
    @Binding var height: CGFloat
    private let minHeight: CGFloat = 58
    private let maxHeight: CGFloat = 260

    var body: some View {
        ZStack(alignment: .top) {
            TextEditor(text: $text)
                .focused(inputFocused)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(height: height)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 10)

            EdgeResizeHandle(height: $height, minHeight: minHeight, maxHeight: maxHeight)
        }
    }
}

struct EdgeResizeHandle: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @State private var startHeight: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 18)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(LinearGradient(colors: [DesignToken.blue.opacity(0.35), DesignToken.cyan.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 72, height: 4)
                    .padding(.top, 7)
            }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help("拖拽输入框上边缘调整高度")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startHeight == nil { startHeight = height }
                    let base = startHeight ?? height
                    height = min(max(base - value.translation.height, minHeight), maxHeight)
                }
                .onEnded { _ in
                    startHeight = nil
                }
        )
    }
}

struct ParameterPanel: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("模型参数")
                .font(.headline)
            VStack(alignment: .leading) {
                Text("Temperature \(String(format: "%.2f", viewModel.settings.temperature))")
                Slider(value: $viewModel.settings.temperature, in: 0...2, step: 0.05)
                    .onChange(of: viewModel.settings.temperature) { _, _ in viewModel.persistSettings() }
            }
            VStack(alignment: .leading) {
                Text("Top P \(String(format: "%.2f", viewModel.settings.topP))")
                Slider(value: $viewModel.settings.topP, in: 0...1, step: 0.05)
                    .onChange(of: viewModel.settings.topP) { _, _ in viewModel.persistSettings() }
            }
            Stepper("Max Tokens：\(viewModel.settings.maxOutputTokens)", value: $viewModel.settings.maxOutputTokens, in: 256...128000, step: 256)
                .onChange(of: viewModel.settings.maxOutputTokens) { _, _ in viewModel.persistSettings() }
            Toggle("启用思考参数", isOn: $viewModel.settings.enableReasoning)
                .onChange(of: viewModel.settings.enableReasoning) { _, _ in viewModel.persistSettings() }
            Picker("思考强度", selection: $viewModel.settings.reasoningEffort) {
                ForEach(["minimal", "low", "medium", "high"], id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .onChange(of: viewModel.settings.reasoningEffort) { _, _ in viewModel.persistSettings() }
        }
        .frame(width: 320)
    }
}

