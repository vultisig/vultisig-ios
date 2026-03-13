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

    // MARK: - Inline Header

    private var inlineHeader: some View {
        ZStack {
            Text("agentConversationsTitle".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            HStack {
                Button {
                    router.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }

                Spacer()

                Menu {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("agentDeleteAllConversations".localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(Theme.colors.textPrimary)
                        .accessibilityLabel("agentMoreOptions".localized)
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
                        Text("agentLoadingConversations".localized)
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

                        Text("agentNoPastConversations".localized)
                            .font(Theme.fonts.title3)
                            .foregroundStyle(Theme.colors.textPrimary)

                        Text("agentStartNewChat".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        PrimaryButton(title: "agentNewChat".localized) {
                            router.navigateBack()
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
            PrimaryButton(title: "agentNewChat".localized) {
                router.navigateBack()
            }
            .padding(.bottom, 16)

            LazyVStack(spacing: 0) {
                ForEach(viewModel.conversations) { conv in
                    conversationRow(conv)
                        .padding(.bottom, 4)
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
            NotificationCenter.default.post(
                name: .agentDidSelectConversation,
                object: conv.id
            )
            router.navigateBack()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conv.title ?? "agentNewChat".localized)
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
