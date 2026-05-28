import SwiftUI
import AppKit

struct WorkspacePanelView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 10) {
            WorkspaceHeaderView(viewModel: viewModel, isCollapsed: $isCollapsed)
            WorkspaceFileBrowserView(viewModel: viewModel)
            WorkspaceTerminalView(viewModel: viewModel)
        }
        .padding(10)
        .background(Color(red: 0.96, green: 0.97, blue: 0.98).opacity(0.92))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignToken.border.opacity(0.5))
                .frame(width: 0.5)
        }
    }
}

struct ResizableWorkspacePanel: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isCollapsed: Bool
    @Binding var width: CGFloat
    @State private var dragStartWidth: CGFloat?
    @State private var dragStartX: CGFloat?

    private let minWidth: CGFloat = 240
    private let maxWidth: CGFloat = 560

    var body: some View {
        ZStack(alignment: .leading) {
            WorkspacePanelView(viewModel: viewModel, isCollapsed: $isCollapsed)
                .frame(width: width)

            ResizeHandle()
                .frame(width: 8)
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStartWidth == nil { dragStartWidth = width }
                            if dragStartX == nil { dragStartX = value.startLocation.x }
                            let delta = value.location.x - (dragStartX ?? value.startLocation.x)
                            let proposedWidth = (dragStartWidth ?? width) - delta
                            width = min(max(proposedWidth, minWidth), maxWidth)
                        }
                        .onEnded { _ in
                            dragStartWidth = nil
                            dragStartX = nil
                        }
                )
        }
        .frame(width: width)
        .animation(nil, value: width)
    }
}

struct ResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }
}

struct WorkspaceHeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(DesignToken.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.workspaceDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(viewModel.workspaceURL?.path ?? "终端 pwd 将在打开工作区后固定到该目录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        isCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
                .help("收起文件和终端")
            }
            if let session = viewModel.metabolismSession {
                HStack(spacing: 6) {
                    Image(systemName: session.isGitHubReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(session.isGitHubReady ? DesignToken.mint : DesignToken.orange)
                    Text("新陈代谢：\(session.branchName)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(session.displayStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DesignToken.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 8) {
                Button { viewModel.openWorkspace() } label: { Label("打开", systemImage: "folder") }
                    .disabled(viewModel.isMetabolismModeActive)
                Button { viewModel.refreshWorkspaceFiles() } label: { Label("更新", systemImage: "arrow.clockwise") }
                    .labelStyle(.titleAndIcon)
                    .disabled(viewModel.workspaceURL == nil)
                Button { viewModel.authorizeAdditionalAccess() } label: { Label("授权", systemImage: "lock.open") }
                Button { viewModel.revealWorkspaceInFinder() } label: { Label("Finder", systemImage: "magnifyingglass") }
                    .disabled(viewModel.workspaceURL == nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.4), lineWidth: 0.5))
    }
}

struct WorkspaceFileBrowserView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("文件", systemImage: "folder")
                    .font(.caption.bold())
                    .foregroundStyle(DesignToken.ink)
                Spacer()
                Text("\(viewModel.visibleWorkspaceFiles.count)/\(viewModel.workspaceFiles.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.1), in: Capsule())
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if viewModel.workspaceFiles.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("打开工作区后显示文件树")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                    ForEach(viewModel.visibleWorkspaceFiles) { item in
                        WorkspaceFileRow(item: item, isSelected: item.id == viewModel.selectedWorkspaceFile?.id, isCollapsed: viewModel.isWorkspaceFolderCollapsed(item)) {
                            viewModel.selectWorkspaceFile(item)
                        } onToggleFolder: {
                            viewModel.toggleWorkspaceFolder(item)
                        } onSendToChat: {
                            viewModel.sendWorkspaceFile(item)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: .infinity)
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DesignToken.border.opacity(0.4)))
        }
        .frame(maxHeight: .infinity)
        .padding(12)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.4), lineWidth: 0.5))
    }
}

struct WorkspaceFileRow: View {
    let item: WorkspaceFileItem
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void
    let onToggleFolder: () -> Void
    let onSendToChat: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Spacer().frame(width: CGFloat(item.depth) * 14)
                if item.isDirectory {
                    Button(action: onToggleFolder) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }
                Image(systemName: fileIcon)
                    .foregroundStyle(fileIconColor)
                    .font(.caption)
                    .frame(width: 16)
                Text(item.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(DesignToken.ink)
            .background(isSelected ? DesignToken.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !item.isDirectory {
                Button("发送到对话") { onSendToChat() }
            }
        }
    }

    private var fileIcon: String {
        if item.isDirectory { return "folder.fill" }
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "text.page"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "html", "htm": return "globe"
        case "css", "scss", "less": return "paintbrush"
        case "json": return "brackets"
        case "xml", "plist": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown", "txt", "rtf": return "doc.plaintext"
        case "yml", "yaml", "toml": return "gearshape"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico": return "photo"
        case "mp3", "wav", "aac", "flac": return "music.note"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "rar", "7z": return "archivebox"
        case "sh", "zsh", "bash", "fish": return "terminal"
        case "c", "cpp", "h", "hpp", "m", "mm": return "c.circle"
        case "java", "kt", "kts": return "cup.and.saucer"
        case "rb": return "diamond"
        case "go": return "g.circle"
        case "rs": return "r.circle"
        case "sql", "db", "sqlite": return "cylinder"
        case "env", "gitignore", "dockerignore": return "lock"
        case "dockerfile": return "shippingbox"
        case "lock": return "lock.fill"
        default: return "doc"
        }
    }

    private var fileIconColor: Color {
        if item.isDirectory { return Color(red: 0.55, green: 0.72, blue: 0.95) }
        let ext = item.url.pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return Color(red: 0.25, green: 0.55, blue: 0.85)
        case "js", "jsx": return Color(red: 0.93, green: 0.80, blue: 0.20)
        case "ts", "tsx": return Color(red: 0.18, green: 0.50, blue: 0.85)
        case "html", "htm": return Color(red: 0.90, green: 0.35, blue: 0.20)
        case "css", "scss": return Color(red: 0.35, green: 0.50, blue: 0.90)
        case "json": return Color(red: 0.60, green: 0.75, blue: 0.20)
        case "md", "txt": return .secondary
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return Color(red: 0.80, green: 0.45, blue: 0.85)
        case "sh", "zsh", "bash": return DesignToken.mint
        default: return DesignToken.muted
        }
    }
}

struct WorkspaceTerminalView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var terminalFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                    Label("终端", systemImage: "terminal")
                    .font(.caption.bold())
                    .foregroundStyle(DesignToken.ink)
                Spacer()
                Button { viewModel.newInteractiveTerminal() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("新建交互式终端")
                Button { viewModel.stopSelectedTerminal() } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.selectedTerminal?.isRunning != true)
                    .help("停止当前终端")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.terminals) { terminal in
                        TerminalTabView(terminal: terminal, isSelected: terminal.id == viewModel.selectedTerminalID) {
                            viewModel.selectedTerminalID = terminal.id
                        } onClose: {
                            viewModel.deleteTerminal(terminal)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            TerminalScrollCaptureView(
                screen: viewModel.selectedTerminal?.screen ?? TerminalScreen(),
                onText: { text in viewModel.sendToSelectedTerminal(text) },
                onBackspace: { viewModel.sendToSelectedTerminal("\u{7f}") },
                onEnter: { viewModel.sendToSelectedTerminal("\n") },
                onTab: { viewModel.sendToSelectedTerminal("\t") },
                onEscape: { viewModel.sendToSelectedTerminal("\u{1b}") },
                onArrowUp: { viewModel.sendToSelectedTerminal("\u{1b}[A") },
                onArrowDown: { viewModel.sendToSelectedTerminal("\u{1b}[B") },
                onArrowRight: { viewModel.sendToSelectedTerminal("\u{1b}[C") },
                onArrowLeft: { viewModel.sendToSelectedTerminal("\u{1b}[D") }
            )
            .focused($terminalFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(Color(red: 0.05, green: 0.06, blue: 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(terminalFocused ? DesignToken.mint.opacity(0.75) : DesignToken.border.opacity(0.60)))
            .onTapGesture { terminalFocused = true }
            .frame(height: 180)

            if let terminal = viewModel.selectedTerminal {
                HStack(spacing: 6) {
                    Circle()
                        .fill(terminal.isRunning ? DesignToken.mint : DesignToken.muted.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(terminal.statusText)
                    Text(terminal.workingDirectory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(terminal.command)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(DesignToken.border))
    }

    private func color(for kind: TerminalLineKind) -> Color {
        switch kind {
        case .input: DesignToken.mint
        case .output: Color.white.opacity(0.90)
        case .system: DesignToken.cyan
        case .error: DesignToken.rose
        }
    }
}

struct TerminalScrollCaptureView: NSViewRepresentable {
    let screen: TerminalScreen
    var onText: (String) -> Void
    var onBackspace: () -> Void
    var onEnter: () -> Void
    var onTab: () -> Void
    var onEscape: () -> Void
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onArrowRight: () -> Void
    var onArrowLeft: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = TerminalTextCaptureNSView()
        textView.configureAppearance()
        update(textView)
        textView.setTerminalScreen(screen)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TerminalTextCaptureNSView else { return }
        update(textView)
        textView.setTerminalScreen(screen)
    }

    private func update(_ textView: TerminalTextCaptureNSView) {
        textView.onText = onText
        textView.onBackspace = onBackspace
        textView.onEnter = onEnter
        textView.onTab = onTab
        textView.onEscape = onEscape
        textView.onArrowUp = onArrowUp
        textView.onArrowDown = onArrowDown
        textView.onArrowRight = onArrowRight
        textView.onArrowLeft = onArrowLeft
    }
}

final class TerminalTextCaptureNSView: NSTextView {
    var onText: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onEnter: (() -> Void)?
    var onTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onArrowRight: (() -> Void)?
    var onArrowLeft: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func configureAppearance() {
        isEditable = false
        isSelectable = true
        drawsBackground = false
        insertionPointColor = .clear
        textContainerInset = NSSize(width: 10, height: 10)
        font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textColor = NSColor.white.withAlphaComponent(0.90)
        allowsUndo = false
        isRichText = false
        isHorizontallyResizable = false
        isVerticallyResizable = true
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        textContainer?.lineFragmentPadding = 0
        autoresizingMask = [.width]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        minSize = .zero
    }

    func setTerminalScreen(_ screen: TerminalScreen) {
        let selectedRange = selectedRange()
        textStorage?.setAttributedString(attributedString(for: screen))
        if selectedRange.location != NSNotFound, selectedRange.upperBound <= string.utf16.count {
            setSelectedRange(selectedRange)
        }
        scrollRangeToVisible(NSRange(location: string.utf16.count, length: 0))
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let visibleWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        textContainer?.containerSize = NSSize(width: max(0, visibleWidth - textContainerInset.wi