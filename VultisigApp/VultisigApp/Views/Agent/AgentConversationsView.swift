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

    var body: some View {
        VStack(spacing: 0) {
            inlineHeader
            Separator(color: Theme.colors.borderLight, opacity: 1)
            content
        }
        .background(Theme.colors.bgPrimary.ignoresSafeArea())
        .confirmationDialog(
            "Delete all conversations?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                guard let vault = appViewModel.selectedVault else { return }
                Task { await viewModel.deleteAllConversations(vault: vault) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your conversations. This cannot be undone.")
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

    // MARK: - Inline Header (root tab — no native NavBar)

    private var inlineHeader: some View {
        ZStack {
            Text("Vultisig")
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            HStack {
                Spacer()
                HStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.isConnected ? Theme.colors.alertSuccess : Theme.colors.textTertiary)
                        .frame(width: 10, height: 10)
                    
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAllConfirm = true
                        } label: {
                            Label("Delete All Conversations", systemImage: "trash")
                        }
                        Button {
                            guard let vault = appViewModel.selectedVault else { return }
                            Task { await viewModel.disconnect(vault: vault) }
                        } label: {
                            Label("Disconnect", systemImage: "power")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .foregroundStyle(Theme.colors.textPrimary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgPrimary)
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
                        Text("Loading conversations...")
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .padding(.top, 8)
                        Spacer()
                    }
                } else if viewModel.conversations.isEmpty {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 40)

                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.colors.turquoise, Theme.colors.primaryAccent3],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("No Past Conversations")
                            .font(Theme.fonts.title3)
                            .foregroundStyle(Theme.colors.textPrimary)

                        Text("Start a new chat to begin interacting with Vulti.")
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // New chat button
                        PrimaryButton(title: "New Chat") {
                            navigateToChat(with: nil)
                        }
                    }
                } else {
                    conversationList
                }
            }
            .padding()
            .padding(.bottom, 32)
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        VStack(spacing: 0) {
            // New chat button
            PrimaryButton(title: "New Chat") {
                navigateToChat(with: nil)
            }
            .padding(.bottom, 16)

            // Past conversations — LazyVStack for proper row virtualisation.
            // (The outer ScrollView already handles scrolling; no inner List needed.)
            LazyVStack(spacing: 0) {
                ForEach(viewModel.conversations) { conv in
                    conversationRow(conv)
                        .padding(.bottom, 4)
                        // Swipe-to-delete (replaces List's .onDelete)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if let idx = viewModel.conversations.firstIndex(where: { $0.id == conv.id }) {
                                    deleteConversations(at: IndexSet(integer: idx))
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(conv.title ?? "New Chat")
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .lineLimit(1)

                    Text(formatDate(conv.updatedAt))
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Theme.colors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
            .padding()
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
        }
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

    // MARK: - Shared formatters (one allocation per view lifetime, not per row)

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formatDate(_ dateStr: String) -> String {
        guard let date = AgentBackendClient.parseISO8601(dateStr) else {
            return dateStr
        }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        AgentConversationsView()
            .environmentObject(AppViewModel())
    }
}
