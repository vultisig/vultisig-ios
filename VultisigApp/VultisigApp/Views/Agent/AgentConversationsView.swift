//
//  AgentConversationsView.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import SwiftUI

struct AgentConversationsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @StateObject private var viewModel = AgentConversationsViewModel()
    @Environment(\.router) private var router

    @State private var showDeleteAllConfirm = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            inlineHeader
            Separator(color: Theme.colors.borderLight, opacity: 1)
            if !viewModel.conversations.isEmpty {
                searchBar
            }
            content
        }
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
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
        .crossPlatformSheet(isPresented: $viewModel.passwordRequired) {
            if let vault = appViewModel.selectedVault {
                AgentPasswordPromptScreen(usesFastVault: true) { password in
                    await viewModel.signIn(vault: vault, password: password)
                }
            }
        }
    }

    // MARK: - Inline Header

    private var inlineHeader: some View {
        ZStack {
            Text("agentSessionHistory".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .lineLimit(1)

            HStack {
                Menu {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("agentDeleteAllConversations".localized, systemImage: "trash")
                    }
                    Button {
                        guard let vault = appViewModel.selectedVault else { return }
                        Task { await viewModel.disconnect(vault: vault) }
                    } label: {
                        Label("agentDisconnect".localized, systemImage: "power")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }

                Spacer()

                Button {
                    navigateToChat(with: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Theme.colors.turquoise)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgPrimary)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            TextField("agentSearchConversations".localized, text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    VStack {
                        Spacer().frame(height: 100)
                        ProgressView()
                            .controlSize(.large)
                            .tint(Theme.colors.turquoise)
                        Text("agentLoadingConversations".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .padding(.top, 8)
                        Spacer()
                    }
                } else if viewModel.conversations.isEmpty {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 40)

                        AgentOrbView(size: 48, animated: false)

                        Text("agentNoPastConversations".localized)
                            .font(Theme.fonts.title3)
                            .foregroundStyle(Theme.colors.textPrimary)

                        Text("agentStartNewChat".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    conversationList
                }
            }
            .padding()
            .padding(.bottom, 32)
        }
    }

    // MARK: - Filtered Conversations

    private var filteredConversations: [AgentConversation] {
        guard !searchText.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter { conv in
            (conv.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredConversations) { conv in
                conversationRow(conv)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if let idx = viewModel.conversations.firstIndex(where: { $0.id == conv.id }) {
                                deleteConversations(at: IndexSet(integer: idx))
                            }
                        } label: {
                            Label("delete".localized, systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func conversationRow(_ conv: AgentConversation) -> some View {
        Button {
            router.navigate(to: AgentRoute.chat(conversationId: conv.id))
        } label: {
            HStack {
                Text(conv.title ?? "agentNewChat".localized)
                    .font(Theme.fonts.bodyMMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding()
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    private func loadData() {
        guard let vault = appViewModel.selectedVault else { return }

        Task {
            await viewModel.checkAuthAndLoad(vault: vault)
        }
    }

    private func navigateToChat(with starter: String?) {
        if let starter {
            UserDefaults.standard.set(starter, forKey: "agent_pending_starter")
        }
        router.navigate(to: AgentRoute.chat(conversationId: nil))
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
        AgentConversationsView()
            .environmentObject(AppViewModel())
    }
}
