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
            HStack(spacing: 8) {
                Button { viewModel.openWorkspace() } label: { Label("打开", systemImage: "folder") }
                Button { viewModel.refreshWorkspaceFiles() } label: { Label("刷新", systemImage: "arrow.clockwise") }
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
        textContainer?.containerSize = NSSize(width: max(0, visibleWidth - textContainerInset.width * 2), height: CGFloat.greatestFiniteMagnitude)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle shortcuts when this terminal view is focused
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        guard event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "c":
            copy(nil)
            return true
        case "v":
            if let text = NSPasteboard.general.string(forType: .string) {
                onText?(text)
            }
            return true
        case "a":
            selectAll(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            _ = performKeyEquivalent(with: event)
            return
        }
        switch event.keyCode {
        case 36, 76:
            onEnter?()
        case 48:
            onTab?()
        case 51:
            onBackspace?()
        case 53:
            onEscape?()
        case 123:
            onArrowLeft?()
        case 124:
            onArrowRight?()
        case 125:
            onArrowDown?()
        case 126:
            onArrowUp?()
        default:
            if event.modifierFlags.contains(.control), let character = event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first {
                let value = character.value
                if value >= 64, value <= 95 {
                    onText?(String(UnicodeScalar(value - 64)!))
                }
            } else if let characters = event.characters, !characters.isEmpty {
                onText?(characters)
            }
        }
    }

    private func attributedString(for screen: TerminalScreen) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.90),
            .backgroundColor: NSColor.clear
        ]
        let text = renderedText(for: screen)
        let result = NSMutableAttributedString(string: text.value, attributes: baseAttributes)
        for segment in text.segments {
            result.addAttributes(attributes(for: segment.style), range: segment.range)
        }
        if let cursorRange = text.cursorRange {
            result.addAttributes([
                .foregroundColor: NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1),
                .backgroundColor: NSColor.systemMint
            ], range: cursorRange)
        }
        return result
    }

    private func renderedText(for screen: TerminalScreen) -> (value: String, cursorRange: NSRange?, segments: [(range: NSRange, style: TerminalTextStyle)]) {
        let firstVisibleRow = max(0, screen.lines.count - screen.visibleLines.count)
        var output = ""
        var cursorRange: NSRange?
        var segments: [(range: NSRange, style: TerminalTextStyle)] = []
        for (visibleOffset, originalCells) in screen.visibleStyledLines.enumerated() {
            let absoluteRow = firstVisibleRow + visibleOffset
            var cells = originalCells
            if absoluteRow == screen.cursorRow {
                if cells.count <= screen.cursorColumn {
                    cells += Array(repeating: TerminalCell(text: " ", style: screen.currentStyle), count: screen.cursorColumn - cells.count + 1)
                }
                let utf16Location = output.utf16.count + cells.prefix(screen.cursorColumn).map(\.text).joined().utf16.count
                let cursorLength = cells.dropFirst(screen.cursorColumn).first?.text.utf16.count ?? 1
                cursorRange = NSRange(location: utf16Location, length: max(cursorLength, 1))
            }
            if cells.isEmpty {
                output += " "
            } else {
                for cell in cells {
                    let location = output.utf16.count
                    output += cell.text
                    segments.append((NSRange(location: location, length: cell.text.utf16.count), cell.style))
                }
            }
            if visibleOffset < screen.visibleLines.count - 1 { output += "\n" }
        }
        return (output, cursorRange, segments)
    }

    private func attributes(for style: TerminalTextStyle) -> [NSAttributedString.Key: Any] {
        let foreground = terminalColor(index: style.isInverse ? style.backgroundIndex : style.foregroundIndex, fallback: NSColor.white.withAlphaComponent(style.isDim ? 0.58 : 0.90))
        let background = terminalColor(index: style.isInverse ? style.foregroundIndex : style.backgroundIndex, fallback: NSColor.clear)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: style.isBold ? .semibold : .regular),
            .foregroundColor: foreground,
            .backgroundColor: background
        ]
        if style.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    private func terminalColor(index: Int?, fallback: NSColor) -> NSColor {
        guard let index else { return fallback }
        let palette: [NSColor] = [
            NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1),
            NSColor(red: 0.94, green: 0.28, blue: 0.36, alpha: 1),
            NSColor(red: 0.28, green: 0.78, blue: 0.48, alpha: 1),
            NSColor(red: 0.94, green: 0.72, blue: 0.28, alpha: 1),
            NSColor(red: 0.36, green: 0.58, blue: 1.00, alpha: 1),
            NSColor(red: 0.76, green: 0.48, blue: 1.00, alpha: 1),
            NSColor(red: 0.28, green: 0.86, blue: 0.92, alpha: 1),
            NSColor(red: 0.88, green: 0.91, blue: 0.96, alpha: 1),
            NSColor(red: 0.42, green: 0.47, blue: 0.56, alpha: 1),
            NSColor(red: 1.00, green: 0.42, blue: 0.50, alpha: 1),
            NSColor(red: 0.42, green: 0.94, blue: 0.62, alpha: 1),
            NSColor(red: 1.00, green: 0.82, blue: 0.38, alpha: 1),
            NSColor(red: 0.54, green: 0.70, blue: 1.00, alpha: 1),
            NSColor(red: 0.86, green: 0.62, blue: 1.00, alpha: 1),
            NSColor(red: 0.48, green: 0.95, blue: 1.00, alpha: 1),
            NSColor.white
        ]
        if index < palette.count { return palette[index] }
        if index >= 232 {
            let value = CGFloat(8 + min(23, index - 232) * 10) / 255
            return NSColor(red: value, green: value, blue: value, alpha: 1)
        }
        if index >= 16 {
            let value = index - 16
            let red = CGFloat(value / 36) / 5
            let green = CGFloat((value / 6) % 6) / 5
            let blue = CGFloat(value % 6) / 5
            return NSColor(red: red, green: green, blue: blue, alpha: 1)
        }
        return fallback
    }
}

struct TerminalTabView: View {
    let terminal: WorkspaceTerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(terminal.isRunning ? DesignToken.mint : DesignToken.muted.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(terminal.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? DesignToken.blue : DesignToken.ink)
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.68), in: Capsule())
        .overlay(Capsule().stroke(isSelected ? DesignToken.blue.opacity(0.25) : DesignToken.border.opacity(0.8)))
    }
}

struct TerminalApprovalView: View {
    let request: TerminalApprovalRequest
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(DesignToken.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 请求执行本地命令")
                        .font(.headline)
                    Text("请确认这个命令可信后再执行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("工作目录")
                    .font(.caption.bold())
                Text(request.workingDirectory)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("命令")
                    .font(.caption.bold())
                Text(request.displayCommand)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignToken.border))
            }

            Text("本地命令可能读写文件、安装依赖或联网。Easy Chat 会实时显示输出，但不会自动判断命令是否安全。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    viewModel.denyPendingTerminalExecution()
                }
                Button("允许执行") {
                    viewModel.approvePendingTerminalExecution()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignToken.orange)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(AppBackground())
    }
}

