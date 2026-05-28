//
//  ContentView.swift
//  metabolic_easy_chat
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

            if viewModel.isShowingAlert {
                BoundedAlertView(message: viewModel.alertMessage) {
                    viewModel.isShowingAlert = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: viewModel.isShowingAlert)
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
        .sheet(item: $viewModel.pendingTerminalApproval) { request in
            TerminalApprovalView(request: request, viewModel: viewModel)
        }
        .onAppear {
            inputFocused = true
        }
    }
}

private struct BoundedAlertView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 16) {
                    Text("提示")
                        .font(.headline)
                        .foregroundStyle(DesignToken.ink)

                    ScrollView {
                        Text(message)
                            .font(.body)
                            .foregroundStyle(DesignToken.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: max(120, proxy.size.height * 0.5 - 112))

                    Button("知道了", action: onDismiss)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(DesignToken.blue)
                }
                .padding(24)
                .frame(width: min(520, proxy.size.width - 48))
                .frame(maxHeight: proxy.size.height * 0.5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                )
                .shadow(color: DesignToken.shadow, radius: 24, y: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    ContentView()
}
