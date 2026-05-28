import SwiftUI

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
    @Environment(\.appUpdateController) private var appUpdateController

    var body: some View {
        VStack(spacing: 16) {
            BrandHeroCard(isMetabolismActive: viewModel.isMetabolismModeActive) {
                appUpdateController.checkForUpdates()
            }
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
                if viewModel.isMetabolismModeActive {
                    HStack(spacing: 8) {
                        Button {
                            Task { await viewModel.leaveMetabolismMode() }
                        } label: {
                            Label("回到原工作区", systemImage: "arrow.uturn.left")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.callout.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isMetabolismWorking)
                        Button {
                            Task { await viewModel.submitMetabolismPullRequest() }
                        } label: {
                            Label("提交并提PR", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.callout.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isMetabolismWorking)
                    }
                } else {
                    Button {
                        Task { await viewModel.startMetabolismMode() }
                    } label: {
                        Label(viewModel.isMetabolismWorking ? "新陈代谢中…" : "EasyChat新陈代谢", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isMetabolismWorking)
                }
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
    var isMetabolismActive = false
    var onCheckUpdates: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(colors: [
                                isMetabolismActive ? DesignToken.orange : Color(red: 0.20, green: 0.36, blue: 1.0),
                                isMetabolismActive ? DesignToken.rose : Color(red: 0.10, green: 0.70, blue: 0.92),
                                isMetabolismActive ? DesignToken.lilac : DesignToken.mint
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Image(systemName: isMetabolismActive ? "arrow.triangle.2.circlepath" : "wand.and.stars")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
                .shadow(color: DesignToken.blue.opacity(0.20), radius: 12, y: 6)
                if let onCheckUpdates {
                    Button(action: onCheckUpdates) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(DesignToken.blue)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.82), in: Circle())
                            .overlay(Circle().stroke(DesignToken.border.opacity(0.8), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("检查更新")
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Easy Chat")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignToken.ink)
                Text(isMetabolismActive ? "新陈代谢模式 · 分支工作区" : "多模型 · 工具 · 工作区")
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

