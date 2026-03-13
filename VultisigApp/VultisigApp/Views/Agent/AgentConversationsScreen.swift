//
//  AgentConversationsScreen.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentConversationsScreen: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @StateObject private var viewModel = AgentConversationsViewModel()
    @Environment(\.router) private var router

    @State private var showDeleteAllConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            conversationList
        }
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .confirmationDialog(
            "agentDeleteAllTitle".localized,
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("agentDeleteAll".localized, role: .destructive) {
                guard let vault = appViewModel.selectedVault else { return }
                Task { await viewModel.deleteAllConversations(vault: vault) }
            }
            Button("cancel".localized, role: .cancel) {}
        } message: {
            Text("agentDeleteAllMessage".localized)
        }
        .onAppear {
            loadData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                router.navigateBack()
            } label: {
                Image("alignment-left")
                    .foregroundStyle(Theme.colors.textPrimary)
            }

            Spacer()

            Text("agentSessionHistory".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .contextMenu {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("agentDeleteAllConversations".localized, systemImage: "trash")
                    }
                }

            Spacer()

            Button {
                router.navigateBack()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.colors.bgPrimary)
                    .frame(width: 28, height: 28)
                    .background(Theme.colors.primaryAccent3)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgPrimary)
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(viewModel.conversations) { conv in
                conversationRow(conv)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func conversationRow(_ conv: AgentConversation) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .agentDidSelectConversation,
                object: conv.id
            )
            router.navigateBack()
        } label: {
            Text(conv.title ?? "agentNewChat".localized)
                .font(Theme.fonts.bodyMRegular)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.colors.bgSurface1)
                .cornerRadius(14)
        }
    }

    // MARK: - Actions

    private func loadData() {
        guard let vault = appViewModel.selectedVault else { return }

        Task {
            await viewModel.checkAuthAndLoad(vault: vault)
        }
    }

    private func deleteConversations(at indexSet: IndexSet) {
        guard let vault = appViewModel.selectedVault else { return }
        for index in indexSet {
            let conv = viewModel.conversations[index]
            Task {
                await viewModel.deleteConversation(id: conv.id, vault: vault)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AgentConversationsScreen()
            .environmentObject(AppViewModel())
    }
}
