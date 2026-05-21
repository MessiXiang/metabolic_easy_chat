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
                    .frame(minWidth: 360)

                    if !isWorkspacePanelCollapsed {
                        ResizableWorkspacePanel(viewModel: viewModel, isCollapsed: $isWorkspacePanelCollapsed, width: $workspacePanelWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .clipped()
                .background(.clear)
                .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isWorkspacePanelCollapsed)
            }
            .scrollContentBackground(.hidden)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        isWorkspacePanelCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isWorkspacePanelCollapsed ? "展开文件和终端" : "收起文件和终端")
            }
        }
        .frame(minWidth: 760, minHeight: 620)
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
        .background(Color.white.opacity(0.58))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignToken.border.opacity(0.75))
                .frame(width: 1)
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
        .padding(14)
        .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(DesignToken.border))
        .shadow(color: DesignToken.shadow.opacity(0.55), radius: 14, y: 8)
    }
}

struct WorkspaceFileBrowserView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("文件", systemImage: "list.bullet.rectangle")
                    .font(.caption.bold())
                    .foregroundStyle(DesignToken.ink)
                Spacer()
                Text("\(viewModel.workspaceFiles.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if viewModel.workspaceFiles.isEmpty {
                            Text("打开工作区后显示文件树。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                        ForEach(viewModel.workspaceFiles) { item in
                            WorkspaceFileRow(item: item, isSelected: item.id == viewModel.selectedWorkspaceFile?.id) {
                                viewModel.selectWorkspaceFile(item)
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(minWidth: 90, maxHeight: .infinity)
                .clipped()
                .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border.opacity(0.75)))

                ScrollView {
                    Text(viewModel.selectedWorkspaceFilePreview.isEmpty ? "选择文件后在这里预览文本内容。" : viewModel.selectedWorkspaceFilePreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(viewModel.selectedWorkspaceFilePreview.isEmpty ? .secondary : DesignToken.ink)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .frame(minWidth: 90, maxHeight: .infinity)
                .clipped()
                .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border.opacity(0.75)))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .padding(12)
        .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(DesignToken.border))
    }
}

struct WorkspaceFileRow: View {
    let item: WorkspaceFileItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Spacer().frame(width: CGFloat(item.depth) * 12)
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text")
                    .foregroundStyle(item.isDirectory ? DesignToken.orange : DesignToken.blue)
                    .frame(width: 16)
                Text(item.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(DesignToken.ink)
            .background(isSelected ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
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
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
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
        if let cursorRange = text.cursorRange {
            result.addAttributes([
                .foregroundColor: NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1),
                .backgroundColor: NSColor.systemMint
            ], range: cursorRange)
        }
        return result
    }

    private func renderedText(for screen: TerminalScreen) -> (value: String, cursorRange: NSRange?) {
        let firstVisibleRow = max(0, screen.lines.count - screen.visibleLines.count)
        var output = ""
        var cursorRange: NSRange?
        for (visibleOffset, originalLine) in screen.visibleLines.enumerated() {
            let absoluteRow = firstVisibleRow + visibleOffset
            var line = originalLine
            if absoluteRow == screen.cursorRow {
                if line.count <= screen.cursorColumn {
                    line += String(repeating: " ", count: screen.cursorColumn - line.count + 1)
                }
                let utf16Location = output.utf16.count + String(line.prefix(screen.cursorColumn)).utf16.count
                let cursorLength = String(line.dropFirst(screen.cursorColumn).prefix(1)).utf16.count
                cursorRange = NSRange(location: utf16Location, length: max(cursorLength, 1))
            }
            output += line.isEmpty ? " " : line
            if visibleOffset < screen.visibleLines.count - 1 { output += "\n" }
        }
        return (output, cursorRange)
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
            Color(red: 0.965, green: 0.975, blue: 1.00)
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.995, blue: 1.00),
                    Color(red: 0.94, green: 0.96, blue: 1.00),
                    Color(red: 1.00, green: 0.96, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [DesignToken.cyan.opacity(0.26), .clear], center: .topLeading, startRadius: 60, endRadius: 620)
            RadialGradient(colors: [DesignToken.rose.opacity(0.18), .clear], center: .bottomLeading, startRadius: 60, endRadius: 520)
            RadialGradient(colors: [DesignToken.orange.opacity(0.22), .clear], center: .bottomTrailing, startRadius: 90, endRadius: 700)
            RadialGradient(colors: [DesignToken.lilac.opacity(0.22), .clear], center: .topTrailing, startRadius: 30, endRadius: 460)
            VStack(spacing: 18) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 1)
                }
            }
            .rotationEffect(.degrees(-8))
            .offset(y: -120)
            Circle()
                .strokeBorder(DesignToken.blue.opacity(0.10), lineWidth: 42)
                .frame(width: 360, height: 360)
                .offset(x: 460, y: -250)
            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .strokeBorder(DesignToken.orange.opacity(0.12), lineWidth: 36)
                .frame(width: 340, height: 220)
                .rotationEffect(.degrees(-18))
                .offset(x: -480, y: 260)
            MeshRibbon()
                .offset(x: 180, y: 230)
            FloatingGlassShapes()
        }
        .ignoresSafeArea()
    }
}

struct FloatingGlassShapes: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [DesignToken.blue.opacity(0.18), DesignToken.cyan.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                .frame(width: 160, height: 48)
                .rotationEffect(.degrees(24))
                .offset(x: -230, y: -250)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [DesignToken.rose.opacity(0.12), DesignToken.orange.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 132, height: 92)
                .rotationEffect(.degrees(-18))
                .offset(x: 330, y: 120)
            Circle()
                .fill(DesignToken.mint.opacity(0.15))
                .frame(width: 92, height: 92)
                .offset(x: -80, y: 310)
        }
    }
}

struct MeshRibbon: View {
    var body: some View {
        HStack(spacing: -18) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DesignToken.blue.opacity(0.10), DesignToken.cyan.opacity(0.16), DesignToken.orange.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 220)
                    .rotationEffect(.degrees(Double(index) * 8 - 16))
                    .blendMode(.multiply)
            }
        }
        .blur(radius: 0.4)
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
            .controlSize(.large)
            .tint(DesignToken.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 18)

            List(selection: $viewModel.selectedConversationID) {
                ForEach(viewModel.conversations) { conversation in
                    HStack(spacing: 10) {
                        Image(systemName: "message.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .frame(width: 28, height: 28)
                            .background(.blue.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(conversation.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(conversation.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
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
                    Label("提供商与模型设置", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(DesignToken.border))
            .shadow(color: DesignToken.shadow, radius: 18, y: 10)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color.white.opacity(0.66))
    }
}

struct BrandHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [DesignToken.blue, DesignToken.cyan, DesignToken.mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "wand.and.stars")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)
                .shadow(color: DesignToken.blue.opacity(0.24), radius: 18, y: 8)
                Spacer()
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(DesignToken.orange)
                    .font(.title3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Easy Chat")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(DesignToken.ink)
                Text("多模型 · 图像上下文 · 工具后台")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignToken.muted)
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.96), Color(red: 0.93, green: 0.97, blue: 1.0).opacity(0.90)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.75), lineWidth: 1))
        .shadow(color: DesignToken.shadow, radius: 24, y: 14)
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
                        MessageBubble(
                            message: message,
                            onDelete: { viewModel.deleteMessage(message) },
                            onRegenerate: {
                                Task { await viewModel.regenerate(from: message) }
                            }
                        )
                            .id(message.id)
                    }

                    if viewModel.isSending {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.composerMode == .image ? "正在生成图片…" : "正在思考…")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding()
                        .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(DesignToken.border))
                        .shadow(color: DesignToken.shadow, radius: 18, y: 10)
                        .padding(.horizontal, 24)
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
        }
    }
}

struct EmptyChatView: View {
    var body: some View {
        VStack(spacing: 22) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(LinearGradient(colors: [DesignToken.blue.opacity(0.13), DesignToken.cyan.opacity(0.18), DesignToken.orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 156, height: 132)
                    .rotationEffect(.degrees(-5))
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [DesignToken.blue, DesignToken.cyan, DesignToken.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("AI")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DesignToken.ink, in: Capsule())
                    .offset(x: 16, y: 10)
            }
            Text("把模型、图像和工具编排成一个画布")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(DesignToken.ink)
            Text("支持 OpenAI 格式的 v1/responses、v1/chat/completions 与图片生成接口。图片 URL 会自动下载并转换为 Base64 保存到上下文。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 10) {
                FeatureTile(icon: "switch.2", title: "多模型")
                FeatureTile(icon: "brain.head.profile", title: "思考")
                FeatureTile(icon: "globe", title: "搜索")
                FeatureTile(icon: "photo", title: "图片上下文")
            }
        }
        .padding(38)
        .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 36).stroke(DesignToken.border))
        .shadow(color: DesignToken.shadow, radius: 32, y: 18)
    }
}

struct FeatureTile: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(DesignToken.blue)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(DesignToken.ink)
        }
        .frame(width: 92, height: 64)
        .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignToken.border))
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let onDelete: () -> Void
    let onRegenerate: () -> Void

    private var toolRequests: [ToolInvocation] {
        ToolInvocationService(settings: ProviderSettings()).extractInvocations(from: message.text)
    }

    private var displayText: String {
        ToolInvocationService(settings: ProviderSettings()).displayTextByHidingInvocations(in: message.text)
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
                    MessageActionBar(message: message, onCopy: copyMessage, onDelete: onDelete, onRegenerate: onRegenerate)
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
                    VStack(alignment: .leading, spacing: 8) {
                        if let nsImage = image.nsImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignToken.border))
                                .frame(maxHeight: 420)
                                .shadow(color: DesignToken.shadow, radius: 16, y: 8)
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

                if !message.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(message.attachments) { attachment in
                            AttachmentChip(attachment: attachment, onRemove: nil)
                        }
                    }
                }

                if !message.toolRuns.isEmpty {
                    ToolRunsView(toolRuns: message.toolRuns)
                }

                if !message.toolInvocations.isEmpty {
                    ToolInvocationsView(records: message.toolInvocations)
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
            Button("重新生成") {
                onRegenerate()
            }
            Button("删除", role: .destructive) {
                onDelete()
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.90, green: 0.95, blue: 1.00), Color(red: 0.96, green: 0.99, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(DesignToken.paper)
    }

    private func copyMessage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.copyText, forType: .string)
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
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                Image(systemName: iconName)
                    .font(.caption.bold())
                    .foregroundStyle(iconColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("申请调用")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DesignToken.ink)
                }
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(DesignToken.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            LinearGradient(colors: [iconColor.opacity(0.08), Color.white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(iconColor.opacity(0.18)))
    }

    private var displayName: String {
        ToolInvocationService(settings: ProviderSettings()).definition(named: invocation.name)?.displayName ?? invocation.name
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

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(markdownBlocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignToken.blue)
                            .frame(minWidth: ordered ? 26 : 14, alignment: .trailing)
                        inlineText(item)
                            .font(.body)
                            .lineSpacing(3)
                    }
                }
            }
        case let .code(value):
            ScrollView(.horizontal, showsIndicators: true) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignToken.border))
        case let .table(rows):
            MarkdownTableView(rows: rows)
        }
    }

    private func inlineText(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(value)
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

    private var markdownBlocks: [MarkdownBlock] {
        MarkdownBlock.parse(text)
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
        case list([String], Bool)
        case code(String)
        case table([[String]])
    }

    let id = UUID()
    let kind: Kind

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(MarkdownBlock(kind: .code(codeLines.joined(separator: "\n"))))
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(MarkdownBlock(kind: .heading(heading.level, heading.text)))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                blocks.append(MarkdownBlock(kind: .divider))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    var value = String(current.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix(">") { value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces) }
                    quoteLines.append(value)
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .quote(quoteLines.joined(separator: "\n"))))
                continue
            }

            if isTableStart(lines, at: index) {
                var tableLines: [String] = []
                while index < lines.count, lines[index].contains("|") {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    if !isTableSeparator(current) { tableLines.append(current) }
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .table(tableLines.map(tableCells))))
                continue
            }

            if let list = parseList(lines, start: index) {
                blocks.append(MarkdownBlock(kind: .list(list.items, list.ordered)))
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
            blocks.append(MarkdownBlock(kind: .paragraph(paragraphLines.joined(separator: "\n"))))
        }

        return blocks.isEmpty ? [MarkdownBlock(kind: .paragraph(text))] : blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func isDivider(_ line: String) -> Bool {
        line.range(of: #"^\s*(-\s*){3,}$"#, options: .regularExpression) != nil
    }

    private static func parseList(_ lines: [String], start: Int) -> (items: [String], ordered: Bool, nextIndex: Int)? {
        guard start < lines.count else { return nil }
        let first = lines[start].trimmingCharacters(in: .whitespaces)
        let ordered = first.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
        let unordered = first.range(of: #"^[-*]\s+"#, options: .regularExpression) != nil
        guard ordered || unordered else { return nil }

        var items: [String] = []
        var index = start
        let pattern = ordered ? #"^\d+\.\s+"# : #"^[-*]\s+"#
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.range(of: pattern, options: .regularExpression) != nil else { break }
            items.append(line.replacingOccurrences(of: pattern, with: "", options: .regularExpression))
            index += 1
        }
        return (items, ordered, index)
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

struct ToolRunsView: View {
    let toolRuns: [ToolRun]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(toolRuns) { run in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: run.status))
                                .foregroundStyle(color(for: run.status))
                            Text(run.title)
                                .font(.caption.weight(.semibold))
                            Spacer()
                        }
                        if !run.output.isEmpty {
                            ScrollView {
                                Text(run.output)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(DesignToken.muted)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                            .padding(10)
                            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignToken.border))
                        } else {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("工具执行中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(DesignToken.blue)
                Text("工具执行 \(completedCount)/\(toolRuns.count)")
                    .font(.caption.weight(.bold))
                Spacer()
            }
            .padding(10)
            .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        case .running: DesignToken.orange
        case .completed: DesignToken.mint
        case .failed: DesignToken.rose
        }
    }
}

struct ToolInvocationsView: View {
    let records: [ToolInvocationRecord]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: record.status))
                                .foregroundStyle(color(for: record.status))
                            Text(record.displayName)
                                .font(.caption.weight(.semibold))
                            Text(record.toolName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let isConfirmed = record.isConfirmed {
                                Text(isConfirmed ? "confirmed" : "denied")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(isConfirmed ? DesignToken.mint : DesignToken.rose)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Input")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(record.input)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                            if !record.output.isEmpty {
                                Divider()
                                Text("Output")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(record.output)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignToken.border))
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(DesignToken.lilac)
                Text("Tool Invocations \(completedCount)/\(records.count)")
                    .font(.caption.weight(.bold))
                Spacer()
            }
            .padding(10)
            .background(DesignToken.lilac.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        case .running: DesignToken.orange
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

    var body: some View {
        HStack(spacing: 6) {
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
                .background(DesignToken.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(DesignToken.border))
                .shadow(color: DesignToken.shadow.opacity(0.75), radius: 16, y: 8)

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
                        .frame(width: 52, height: 52)
                        .background(
                            LinearGradient(colors: viewModel.isSending ? [DesignToken.rose, DesignToken.orange] : (viewModel.composerMode == .image ? [DesignToken.lilac, DesignToken.rose] : [DesignToken.blue, DesignToken.cyan]), startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .shadow(color: (viewModel.isSending ? DesignToken.rose : (viewModel.composerMode == .image ? DesignToken.lilac : DesignToken.blue)).opacity(0.26), radius: 16, y: 8)
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
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
            LinearGradient(colors: [DesignToken.blue.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result {
                urls.forEach { viewModel.addFileAttachment(from: $0) }
            }
        }
    }

    private var composerToolbar: some View {
        HStack(spacing: 6) {
            Button {
                isShowingFileImporter = true
            } label: {
                Image(systemName: "paperclip")
            }
            .buttonStyle(.borderless)
            .help("添加附件")

            Picker("模型", selection: $viewModel.settings.chatModel) {
                ForEach(viewModel.settings.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .controlSize(.small)
            .onChange(of: viewModel.settings.chatModel) { _, _ in viewModel.persistSettings() }

            Picker("模式", selection: $viewModel.composerMode) {
                ForEach(ComposerMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 74)
            .controlSize(.small)

            Toggle(isOn: $viewModel.settings.useResponsesAPI) {
                Image(systemName: "bolt")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help(viewModel.settings.useResponsesAPI ? "当前使用 Responses API" : "当前使用 Chat Completions API")
            .onChange(of: viewModel.settings.useResponsesAPI) { _, _ in viewModel.persistSettings() }

            Toggle(isOn: $viewModel.settings.enableReasoning) {
                Image(systemName: "brain.head.profile")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help(viewModel.settings.enableReasoning ? "已启用思考参数" : "未启用思考参数")
            .onChange(of: viewModel.settings.enableReasoning) { _, _ in viewModel.persistSettings() }

            if viewModel.settings.enableReasoning {
                Picker("思考长度", selection: $viewModel.settings.reasoningEffort) {
                    ForEach(["minimal", "low", "medium", "high"], id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 76)
                .controlSize(.small)
                .onChange(of: viewModel.settings.reasoningEffort) { _, _ in viewModel.persistSettings() }
            }

            if viewModel.composerMode == .image {
                Picker("尺寸", selection: $viewModel.imageSize) {
                    ForEach(["1024x1024", "1024x1536", "1536x1024"], id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 104)
                .controlSize(.small)
            }

            Spacer(minLength: 4)

            Text("⌘↩")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.regenerateLastAssistant() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .help("重新生成上一条")
            .disabled(viewModel.isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
            .frame(height: 12)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(LinearGradient(colors: [DesignToken.blue.opacity(0.35), DesignToken.cyan.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 72, height: 4)
                    .padding(.top, 4)
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
