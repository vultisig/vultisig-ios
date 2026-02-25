//
//  AgentConversationsViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import OSLog

@MainActor
final class AgentConversationsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var conversations: [AgentConversation] = []
    @Published var starters: [String] = []
    @Published var isLoading = false
    @Published var isConnected = false
    @Published var error: String?

    // MARK: - Private

    private let backendClient = AgentBackendClient()
    private let authService = AgentAuthService.shared
    private let logger = Logger(subsystem: "com.vultisig", category: "AgentConversationsVM")

    private var startersRefreshTimer: Timer?
    private var lastStartersRefresh: Date?

    // MARK: - Load Conversations

    func loadConversations(vault: Vault) async {
        let token = await getValidToken(vault: vault)
        print("[AgentConvos] 📝 loadConversations: token=\(token != nil ? "present" : "none")")

        isConnected = true
        isLoading = true
        error = nil

        do {
            let response = try await backendClient.listConversations(
                publicKey: vault.pubKeyECDSA,
                skip: 0,
                take: 50,
                token: token?.token ?? ""
            )
            conversations = response.conversations
            print("[AgentConvos] ✅ Loaded \(response.conversations.count) conversations")
            logger.info("Loaded \(response.conversations.count) conversations")
        } catch {
            print("[AgentConvos] ❌ Failed to load conversations: \(error)")
            logger.error("Failed to load conversations: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Load Starters

    func loadStarters(vault: Vault) async {
        // Refresh every 30 minutes
        if let lastRefresh = lastStartersRefresh,
           Date().timeIntervalSince(lastRefresh) < 30 * 60,
           !starters.isEmpty {
            return
        }

        let token = await getValidToken(vault: vault)

        do {
            let context = AgentContextBuilder.buildContext(vault: vault)
            let request = AgentGetStartersRequest(
                publicKey: vault.pubKeyECDSA,
                context: context
            )

            let response = try await backendClient.getStarters(
                request: request,
                token: token?.token ?? ""
            )

            if response.starters.isEmpty {
                starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
            } else {
                starters = Array(response.starters.shuffled().prefix(4))
            }

            lastStartersRefresh = Date()
        } catch {
            logger.warning("Failed to load starters, using fallback: \(error.localizedDescription)")
            starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
        }
    }

    // MARK: - Create Conversation

    func createConversation(vault: Vault) async -> String? {
        let token = await getValidToken(vault: vault)

        do {
            let conv = try await backendClient.createConversation(
                publicKey: vault.pubKeyECDSA,
                token: token?.token ?? ""
            )
            return conv.id
        } catch {
            logger.error("Failed to create conversation: \(error.localizedDescription)")
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Delete Conversation

    func deleteConversation(id: String, vault: Vault) async {
        let token = await getValidToken(vault: vault)

        do {
            try await backendClient.deleteConversation(
                id: id,
                publicKey: vault.pubKeyECDSA,
                token: token?.token ?? ""
            )
            conversations.removeAll { $0.id == id }
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    // MARK: - Auth

    func checkConnection(vault: Vault) {
        // Agent backend uses public_key for identity, no auth token needed
        print("[AgentConvos] 🔌 checkConnection: always connected (public_key auth)")
        isConnected = true
    }

    // MARK: - Helpers

    private func getValidToken(vault: Vault) async -> AgentAuthToken? {
        if let token = authService.getCachedToken(vaultPubKey: vault.pubKeyECDSA) {
            return token
        }
        return await authService.refreshIfNeeded(vaultPubKey: vault.pubKeyECDSA)
    }

    func dismissError() {
        error = nil
    }

    deinit {
        startersRefreshTimer?.invalidate()
    }
}
