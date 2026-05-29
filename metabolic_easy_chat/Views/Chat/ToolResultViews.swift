import SwiftUI

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
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("编辑此消息并重新生成")
            }

            Button {
                onCopy()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("复制整条消息内容")

            Button {
                onRegenerate()
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(message.role == .user ? "从这条用户消息重新生成，并移除后续分支" : "重新生成这条 AI 回复，并移除后续分支")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
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

