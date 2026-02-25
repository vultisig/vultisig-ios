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

    var body: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            content
        }
        .navigationTitle("Vulti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                connectionButton
            }
        }
        .onAppear {
            loadData()
        }
    }

    // MARK: - Content

    private var content: some View {
        VaultMainScreenScrollView(showsIndicators: false, contentInset: 78, scrollOffset: .constant(0)) {
            VStack(spacing: 16) {
                if viewModel.conversations.isEmpty {
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
                            .font(.title2.bold())
                            .foregroundColor(Theme.colors.textPrimary)
                        
                        Text("Start a new chat to begin interacting with Vulti.")
                            .font(.subheadline)
                            .foregroundColor(Theme.colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // New chat button
                        Button {
                            navigateToChat(with: nil)
                        } label: {
                            HStack {
                                Image(systemName: "plus.bubble.fill")
                                    .foregroundColor(Theme.colors.surface)
                                Text("New Chat")
                                    .font(.body.bold())
                                    .foregroundColor(Theme.colors.surface)
                            }
                            .padding()
                            .background(Theme.colors.turquoise)
                            .cornerRadius(12)
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
            Button {
                navigateToChat(with: nil)
            } label: {
                HStack {
                    Image(systemName: "plus.bubble.fill")
                        .foregroundColor(Theme.colors.turquoise)
                    Text("New Chat")
                        .font(.body.bold())
                        .foregroundColor(Theme.colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.colors.textTertiary)
                }
                .padding()
                .background(Theme.colors.bgSurface1)
                .cornerRadius(12)
            }
            .padding(.bottom, 16)

            // Past conversations
            ForEach(viewModel.conversations) { conv in
                conversationRow(conv)
            }
        }
    }

    private func conversationRow(_ conv: AgentConversation) -> some View {
        Button {
            router.navigate(to:AgentRoute.chat(conversationId: conv.id))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conv.title ?? "New Chat")
                        .font(.body)
                        .foregroundColor(Theme.colors.textPrimary)
                        .lineLimit(1)

                    Text(formatDate(conv.updatedAt))
                        .font(.caption)
                        .foregroundColor(Theme.colors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Theme.colors.textTertiary)
            }
            .padding()
            .background(Theme.colors.bgSurface1)
            .cornerRadius(12)
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteConversation(conv)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Connection Button

    private var connectionButton: some View {
        Circle()
            .fill(viewModel.isConnected ? Theme.colors.alertSuccess : Color.gray)
            .frame(width: 10, height: 10)
    }

    // MARK: - Actions

    private func loadData() {
        guard let vault = appViewModel.selectedVault else { return }
        viewModel.checkConnection(vault: vault)

        Task {
            await viewModel.loadConversations(vault: vault)
            await viewModel.loadStarters(vault: vault)
        }
    }

    private func navigateToChat(with starter: String?) {
        router.navigate(to:AgentRoute.chat(conversationId: nil))
        if let starter {
            UserDefaults.standard.set(starter, forKey: "agent_pending_starter")
        }
    }

    private func deleteConversation(_ conv: AgentConversation) {
        guard let vault = appViewModel.selectedVault else { return }
        Task {
            await viewModel.deleteConversation(id: conv.id, vault: vault)
        }
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        AgentConversationsView()
            .environmentObject(AppViewModel())
    }
}
