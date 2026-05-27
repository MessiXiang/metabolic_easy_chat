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

#Preview {
    ContentView()
}
