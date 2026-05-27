//
//  ContentView.swift
//  easy_chat
//
//  Created by 向滢澔 on 2026/5/19.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var isWorkspacePanelCollapsed = false
    @State private var workspacePanelWidth: CGFloat = 340
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            AppBackground()

            NavigationSplitView {
                SidebarView(viewModel: viewModel, isWorkspacePanelCollapsed: $isWorkspacePanelCollapsed)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
            } detail: {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        MessageListView(viewModel: viewModel)
                        ComposerView(viewModel: viewModel, inputFocused: $inputFocused)
                    }
                    .background(.clear)
                    .frame(minWidth: 420)
                    .layoutPriority(1)

                    if !isWorkspacePanelCollapsed {
                        ResizableWorkspacePanel(viewModel: viewModel, isCollapsed: $isWorkspacePanelCollapsed, width: $workspacePanelWidth)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.82)),
                                removal: .move(edge: .trailing).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.9))
                            ))
                    }
                }
                .clipped()
                .background(.clear)
                .animation(.spring(response: 0.38, dampingFraction: 0.84), value: isWorkspacePanelCollapsed)
            }
            .scrollContentBackground(.hidden)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        isWorkspacePanelCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isWorkspacePanelCollapsed ? "sidebar.right" : "sidebar.right")
                        .symbolEffect(.bounce, value: isWorkspacePanelCollapsed)
                }
                .help(isWorkspacePanelCollapsed ? "展开文件和终端" : "收起文件和终端")
            }
        }
        .frame(minWidth: 860, minHeight: 660)
        .preferredColorScheme(.light)
        .sheet(isPresented: $viewModel.isShowingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .alert("提示", isPresented: $viewModel.isShowingAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage)
        }
        .sheet(item: $viewModel.pendingTerminalApproval) { request in
            TerminalApprovalView(request: request, viewModel: viewModel)
        }
        .onAppear {
            inputFocused = true
        }
    }
}

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

struct DesignToken {
    static let ink = Color(red: 0.07, green: 0.09, blue: 0.16)
    static let muted = Color(red: 0.42, green: 0.48, blue: 0.58)
    static let blue = Color(red: 0.12, green: 0.30, blue: 1.00)
    static let cyan = Color(red: 0.00, green: 0.74, blue: 0.95)
    static let orange = Color(red: 1.00, green: 0.52, blue: 0.18)
    static let lilac = Color(red: 0.58, green: 0.36, blue: 1.00)
    static let border = Color(red: 0.80, green: 0.86, blue: 0.94)
    static let paper = Color.white.opacity(0.90)
    static let shadow = Color(red: 0.08, green: 0.12, blue: 0.22).opacity(0.13)
    static let mint = Color(red: 0.22, green: 0.94, blue: 0.70)
    static let rose = Color(red: 1.00, green: 0.28, blue: 0.56)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.975, blue: 0.99)

            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: [
                Color(red: 0.94, green: 0.96, blue: 1.0),
                Color(red: 0.96, green: 0.97, blue: 1.0),
                Color(red: 0.98, green: 0.96, blue: 0.99),
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.97, green: 0.98, blue: 1.0),
                Color(red: 0.99, green: 0.97, blue: 0.96),
                Color(red: 0.96, green: 0.98, blue: 0.99),
                Color(red: 0.97, green: 0.97, blue: 1.0),
                Color(red: 0.98, green: 0.97, blue: 0.97)
            ])
            .opacity(0.9)
        }
        .ignoresSafeArea()
        .drawingGroup()
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isWorkspacePanelCollapsed: Bool

    var body: some View {
        VStack(spacing: 16) {
            BrandHeroCard()
                .padding(.horizontal, 14)
                .padding(.top, 14)

            Button {
                viewModel.startNewConversation()
            } label: {
                Label("新对话", systemImage: "plus.message.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(DesignToken.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 18)

            List(selection: $viewModel.selectedConversationID) {
                ForEach(viewModel.conversations) { conversation in
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption)
                            .foregroundStyle(DesignToken.blue.opacity(0.8))
                            .frame(width: 26, height: 26)
                            .background(DesignToken.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(conversation.id)
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            viewModel.deleteConversation(conversation)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(spacing: 8) {
                Button {
                    viewModel.isShowingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.5), lineWidth: 0.5))
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.99).opacity(0.94))
    }
}

struct BrandHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(colors: [
                                Color(red: 0.20, green: 0.36, blue: 1.0),
                                Color(red: 0.10, green: 0.70, blue: 0.92),
                                DesignToken.mint
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Image(systemName: "wand.and.stars")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
                .shadow(color: DesignToken.blue.opacity(0.20), radius: 12, y: 6)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Easy Chat")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignToken.ink)
                Text("多模型 · 工具 · 工作区")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignToken.muted)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.80))
                .shadow(color: DesignToken.shadow.opacity(0.6), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }
}

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

struct MarkdownMessageText: View {
    let text: String
    let isStreaming: Bool
    @State private var parsedText: String
    @State private var parsedBlocks: [MarkdownBlock]
    @State private var pendingParse: DispatchWorkItem?

    init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
        let initialText = isStreaming ? MarkdownStreamingBuffer.renderablePrefix(text) : text
        _parsedText = State(initialValue: initialText)
        _parsedBlocks = State(initialValue: MarkdownBlock.parse(initialText))
    }

    var body: some View {
        Group {
            if MarkdownInlineRenderer.isPlainText(text) {
                Text(text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(parsedBlocks) { block in
                        blockView(block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: text) { _, newValue in
            scheduleParse(newValue)
        }
        .onDisappear {
            pendingParse?.cancel()
            pendingParse = nil
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level, value):
            inlineText(value)
                .font(headingFont(level))
                .foregroundStyle(DesignToken.ink)
                .padding(.top, level == 1 ? 4 : 2)
        case let .quote(value):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(DesignToken.blue.opacity(0.42))
                    .frame(width: 4)
                inlineText(value)
                    .font(.body)
                    .foregroundStyle(DesignToken.muted)
                    .lineSpacing(4)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 10)
            .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .divider:
            Rectangle()
                .fill(DesignToken.border)
                .frame(height: 1)
                .padding(.vertical, 6)
        case let .paragraph(value):
            inlineText(value)
                .font(.body)
                .lineSpacing(4)
        case let .list(items, ordered):
            MarkdownListView(items: items, ordered: ordered)
        case let .code(language, value, isComplete):
            CodeBlockView(language: language, code: value, isComplete: isComplete)
        case let .table(rows):
            MarkdownTableView(rows: rows)
        }
    }

    private func inlineText(_ value: String) -> Text {
        MarkdownInlineRenderer.text(value)
    }

    private func scheduleParse(_ newValue: String) {
        let renderable = isStreaming ? MarkdownStreamingBuffer.renderablePrefix(newValue) : newValue
        guard renderable != parsedText else { return }

        if isStreaming {
            pendingParse?.cancel()
            let work = DispatchWorkItem {
                parsedText = renderable
                parsedBlocks = MarkdownBlock.parse(renderable)
            }
            pendingParse = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        } else {
            parsedText = renderable
            parsedBlocks = MarkdownBlock.parse(renderable)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline.bold()
        case 4: .subheadline.bold()
        case 5: .caption.bold()
        default: .caption2.bold()
        }
    }

}

struct MarkdownListItem: Hashable {
    var marker: String
    var text: String
    var children: [MarkdownListBlock] = []
}

struct MarkdownListBlock: Hashable {
    var ordered: Bool
    var items: [MarkdownListItem]
}

struct MarkdownListView: View {
    let items: [MarkdownListItem]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? orderedMarker(for: item, fallback: index + 1) : "•")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignToken.blue)
                            .frame(width: ordered ? 34 : 14, alignment: .trailing)
                        MarkdownInlineRenderer.text(item.text)
                            .font(.body)
                            .lineSpacing(3)
                    }
                    ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                        MarkdownListView(items: child.items, ordered: child.ordered)
                            .padding(.leading, ordered ? 34 : 22)
                    }
                }
            }
        }
    }

    private func orderedMarker(for item: MarkdownListItem, fallback: Int) -> String {
        item.marker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(fallback)." : item.marker
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    let isComplete: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.lowercase)
                        .padding(.leading, 12)
                        .padding(.top, 8)
                }
                if !isComplete {
                    Text("正在接收代码…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DesignToken.orange)
                        .padding(.top, 8)
                }
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(copied ? DesignToken.mint : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.6), in: Capsule())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 8)
                .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(CodeHighlighter.highlight(code, language: language))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignToken.border.opacity(0.5)))
    }
}

struct MarkdownTableView: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inlineMarkdown: cell)
                                .font(rowIndex == 0 ? .caption.weight(.bold) : .caption)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(minWidth: 90, maxWidth: 220, alignment: .leading)
                                .background(rowIndex == 0 ? Color.blue.opacity(0.09) : Color.white.opacity(rowIndex.isMultiple(of: 2) ? 0.58 : 0.34))
                                .border(DesignToken.border.opacity(0.8), width: 0.5)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
    }
}

extension Text {
    init(inlineMarkdown value: String) {
        if let attributed = try? AttributedString(markdown: value, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            self.init(attributed)
        } else {
            self.init(value)
        }
    }
}

struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case quote(String)
        case divider
        case paragraph(String)
        case list([MarkdownListItem], Bool)
        case code(String?, String, Bool)
        case table([[String]])

        var cacheKey: String {
            switch self {
            case let .heading(level, value):
                return "heading-\(level)-\(value.hashValue)"
            case let .quote(value):
                return "quote-\(value.hashValue)"
            case .divider:
                return "divider"
            case let .paragraph(value):
                return "paragraph-\(value.hashValue)"
            case let .list(items, ordered):
                return "list-\(ordered)-\(items.hashValue)"
            case let .code(language, value, isComplete):
                return "code-\(language ?? "")-\(isComplete)-\(value.hashValue)"
            case let .table(rows):
                return "table-\(rows.hashValue)"
            }
        }
    }

    let id: String
    let kind: Kind

    init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        func append(_ kind: Kind) {
            blocks.append(MarkdownBlock(id: "\(blocks.count)-\(kind.cacheKey)", kind: kind))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = fenceLanguage(from: trimmed)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                let isComplete = index < lines.count
                if isComplete { index += 1 }
                if isComplete || !codeLines.isEmpty || language != nil {
                    append(.code(language, codeLines.joined(separator: "\n"), isComplete))
                } else {
                    append(.paragraph(line))
                }
                continue
            }

            if let heading = parseHeading(trimmed) {
                append(.heading(heading.level, heading.text))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") || current.isEmpty else { break }
                    if current.isEmpty {
                        // Empty line between quote blocks — check if next line continues the quote
                        if index + 1 < lines.count, lines[index + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                            index += 1
                            continue
                        } else {
                            break
                        }
                    }
                    var value = String(current.dropFirst())
                    if value.hasPrefix(" ") { value = String(value.dropFirst()) }
                    if value.hasPrefix(">") { value = String(value.dropFirst()).trimmingCharacters(in: .init(charactersIn: " ")) }
                    if value.isEmpty {
                        quoteLines.append("")
                    } else {
                        quoteLines.append(value)
                    }
                    index += 1
                }
                // Join lines, collapsing multiple empty lines into one
                let joined = quoteLines.joined(separator: " ").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                append(.quote(joined))
                continue
            }

            if isTableStart(lines, at: index) {
                var tableLines: [String] = []
                while index < lines.count, lines[index].contains("|") {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if !isTableSeparator(current) { tableLines.append(current) }
                    index += 1
                }
                append(.table(tableLines.map(tableCells)))
                continue
            }

            if let list = parseList(lines, start: index) {
                append(.list(list.block.items, list.block.ordered))
                index = list.nextIndex
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("```") || next.hasPrefix(">") || isDivider(next) || parseHeading(next) != nil || isTableStart(lines, at: index) || parseList(lines, start: index) != nil { break }
                paragraphLines.append(next)
                index += 1
            }
            append(.paragraph(paragraphLines.joined(separator: "\n")))
        }

        return blocks.isEmpty ? [MarkdownBlock(id: "0-empty", kind: .paragraph(text))] : blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func fenceLanguage(from line: String) -> String? {
        let value = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private static func isDivider(_ line: String) -> Bool {
        line.range(of: #"^\s*(-\s*){3,}$"#, options: .regularExpression) != nil
    }

    private static func parseList(_ lines: [String], start: Int) -> (block: MarkdownListBlock, nextIndex: Int)? {
        guard start < lines.count else { return nil }
        guard let firstMarker = parseListMarker(lines[start]) else { return nil }
        return parseListBlock(lines, start: start, baseIndent: firstMarker.indent, ordered: firstMarker.ordered)
    }

    private static func parseListBlock(_ lines: [String], start: Int, baseIndent: Int, ordered: Bool) -> (block: MarkdownListBlock, nextIndex: Int)? {
        var items: [MarkdownListItem] = []
        var index = start

        while index < lines.count {
            guard let marker = parseListMarker(lines[index]), marker.indent == baseIndent, marker.ordered == ordered else { break }
            var item = MarkdownListItem(marker: marker.marker, text: marker.text)
            index += 1

            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                    continue
                }
                guard let nextMarker = parseListMarker(lines[index]) else { break }
                if nextMarker.indent <= baseIndent { break }
                guard let child = parseListBlock(lines, start: index, baseIndent: nextMarker.indent, ordered: nextMarker.ordered) else { break }
                item.children.append(child.block)
                index = child.nextIndex
            }

            items.append(item)
        }

        guard !items.isEmpty else { return nil }
        return (MarkdownListBlock(ordered: ordered, items: items), index)
    }

    private static func parseListMarker(_ line: String) -> (indent: Int, ordered: Bool, marker: String, text: String)? {
        guard let match = line.firstMatch(of: /^(\s*)((\d+)\.|[-*])\s+(.*)$/) else { return nil }
        let marker = String(match.2)
        return (
            indent: String(match.1).count,
            ordered: marker.hasSuffix("."),
            marker: marker,
            text: String(match.4)
        )
    }

    private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return lines[index].contains("|") && isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.range(of: #"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#, options: .regularExpression) != nil
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

enum MarkdownInlineRenderer {
    private static let markdownScalars = CharacterSet(charactersIn: "*_`[<\\")

    static func isPlainText(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        if value.rangeOfCharacter(from: markdownScalars) != nil { return false }
        if value.range(of: #"(?m)^\s*(#{1,6}\s|[-*]\s|\d+\.\s|>|---+\s*$|\|.*\|)"#, options: .regularExpression) != nil { return false }
        return true
    }

    static func text(_ value: String) -> Text {
        if isPlainText(value) {
            return Text(value)
        }
        if let attributed = try? AttributedString(markdown: value, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(value)
    }
}

enum CodeHighlighter {
    private static let keywordColor = Color(red: 0.52, green: 0.22, blue: 0.72)
    private static let stringColor = Color(red: 0.08, green: 0.48, blue: 0.24)
    private static let commentColor = Color(red: 0.42, green: 0.48, blue: 0.56)
    private static let numberColor = Color(red: 0.10, green: 0.34, blue: 0.72)

    private static let keywordsByLanguage: [String: Set<String>] = [
        "swift": ["actor", "any", "as", "async", "await", "break", "case", "catch", "class", "continue", "defer", "do", "else", "enum", "extension", "false", "for", "func", "guard", "if", "import", "in", "init", "is", "let", "nil", "private", "protocol", "public", "return", "self", "static", "struct", "switch", "throw", "throws", "true", "try", "var", "where", "while"],
        "javascript": ["await", "break", "case", "catch", "class", "const", "continue", "default", "else", "export", "false", "finally", "for", "from", "function", "if", "import", "let", "new", "null", "return", "switch", "this", "throw", "true", "try", "undefined", "var", "while", "yield"],
        "typescript": ["await", "break", "case", "catch", "class", "const", "continue", "default", "else", "enum", "export", "false", "finally", "for", "from", "function", "if", "implements", "import", "interface", "let", "new", "null", "private", "protected", "public", "readonly", "return", "switch", "this", "throw", "true", "try", "type", "undefined", "var", "while", "yield"],
        "python": ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "elif", "else", "except", "False", "finally", "for", "from", "if", "import", "in", "is", "lambda", "None", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"],
        "json": ["true", "false", "null"],
        "bash": ["case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "then", "while"],
        "shell": ["case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "then", "while"]
    ]

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = DesignToken.ink
        guard !code.isEmpty else { return attributed }

        let normalizedLanguage = normalized(language)
        colorMatches(in: code, attributed: &attributed, pattern: #"//.*|#.*|/\*[\s\S]*?\*/"#, color: commentColor)
        colorMatches(in: code, attributed: &attributed, pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, color: stringColor)
        colorMatches(in: code, attributed: &attributed, pattern: #"\b\d+(?:\.\d+)?\b"#, color: numberColor)

        let keywords = keywordsByLanguage[normalizedLanguage] ?? keywordsByLanguage["swift"] ?? []
        if !keywords.isEmpty {
            let escaped = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            colorMatches(in: code, attributed: &attributed, pattern: #"\b("# + escaped + #")\b"#, color: keywordColor, weight: .semibold)
        }

        return attributed
    }

    private static func normalized(_ language: String?) -> String {
        switch language?.lowercased() {
        case "js", "jsx": "javascript"
        case "ts", "tsx": "typescript"
        case "py": "python"
        case "sh", "zsh", "shellscript": "shell"
        default: language?.lowercased() ?? ""
        }
    }

    private static func colorMatches(in source: String, attributed: inout AttributedString, pattern: String, color: Color, weight: Font.Weight? = nil) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: nsRange) {
            guard let range = Range(match.range, in: source), let attributedRange = Range(range, in: attributed) else { continue }
            attributed[attributedRange].foregroundColor = color
            if let weight {
                attributed[attributedRange].font = .system(.callout, design: .monospaced).weight(weight)
            }
        }
    }
}

enum MarkdownStreamingBuffer {
    private static let maxBufferedCharacters = 1_200

    static func renderablePrefix(_ markdown: String) -> String {
        guard markdown.count > maxBufferedCharacters else { return markdown }

        var inFence = false
        var lastBoundary: String.Index?
        var index = markdown.startIndex
        var lineStart = markdown.startIndex

        while index < markdown.endIndex {
            if markdown[index] == "\n" {
                let line = String(markdown[lineStart..<index]).trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("```") {
                    inFence.toggle()
                }
                let next = markdown.index(after: index)
                if !inFence, next < markdown.endIndex, markdown[next] == "\n" {
                    lastBoundary = markdown.index(after: next)
                }
                lineStart = next
            }
            index = markdown.index(after: index)
        }

        guard let boundary = lastBoundary else { return markdown }
        let bufferedLength = markdown.distance(from: boundary, to: markdown.endIndex)
        return bufferedLength > maxBufferedCharacters ? markdown : String(markdown[..<boundary])
    }
}

struct ToolRunsView: View {
    let toolRuns: [ToolRun]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(toolRuns) { run in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: run.status))
                            .font(.system(size: 9))
                            .foregroundStyle(color(for: run.status))
                        Text(run.title)
                            .font(.caption2.weight(.medium))
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    if !run.output.isEmpty {
                        Text(run.output.prefix(100) + (run.output.count > 100 ? "…" : ""))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(completedCount)/\(toolRuns.count) 工具完成")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.06), in: Capsule())
        }
    }

    private var completedCount: Int {
        toolRuns.filter { $0.status == .completed }.count
    }

    private func icon(for status: ToolRunStatus) -> String {
        switch status {
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func color(for status: ToolRunStatus) -> Color {
        switch status {
        case .running: .secondary
        case .completed: DesignToken.mint
        case .failed: DesignToken.rose
        }
    }
}

struct ToolInvocationsView: View {
    let records: [ToolInvocationRecord]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(records) { record in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: record.status))
                            .font(.system(size: 9))
                            .foregroundStyle(color(for: record.status))
                        Text(record.displayName)
                            .font(.caption2.weight(.medium))
                        Spacer()
                        if let isConfirmed = record.isConfirmed {
                            Image(systemName: isConfirmed ? "checkmark" : "xmark")
                                .font(.system(size: 8))
                                .foregroundStyle(isConfirmed ? DesignToken.mint : DesignToken.rose)
                        }
                    }
                    .padding(.vertical, 2)
                    if !record.output.isEmpty {
                        Text(record.output.prefix(120) + (record.output.count > 120 ? "…" : ""))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(completedCount)/\(records.count) 工具完成")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.06), in: Capsule())
        }
    }

    private var completedCount: Int {
        records.filter(\.isComplete).count
    }

    private func icon(for status: ToolRunStatus) -> String {
        switch status {
        case .running: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func color(for status: ToolRunStatus) -> Color {
        switch status {
        case .running: .secondary
        case .completed: DesignToken.mint
        case .failed: DesignToken.rose
        }
    }
}

struct MessageActionBar: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if message.role == .user {
                Button {
                    onEdit()
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("编辑此消息并重新生成")
            }

            Button {
                onCopy()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("复制整条消息内容")

            Button {
                onRegenerate()
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(message.role == .user ? "从这条用户消息重新生成，并移除后续分支" : "重新生成这条 AI 回复，并移除后续分支")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("从当前对话上下文中删除这条消息")

            if let tokenCount = message.tokenCount {
                Text("\(tokenCount) tok")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.12), in: Capsule())
            }
        }
        .font(.caption)
    }
}

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

#Preview {
    ContentView()
}
