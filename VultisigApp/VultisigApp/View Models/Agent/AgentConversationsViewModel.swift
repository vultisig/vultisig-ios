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
    @Published var passwordRequired = false
    @Published var error: String?

    // MARK: - Private

    private let backendClient = AgentBackendClient()
    private let authService = AgentAuthService.shared
    private let logger = Logger(subsystem: "com.vultisig", category: "AgentConversationsVM")

    private var startersRefreshTimer: Timer?
    private var lastStartersRefresh: Date?

    // MARK: - Load Conversations

    func checkAuthAndLoad(vault: Vault) async {
        isLoading = true
        let token = await getValidToken(vault: vault)
        
        if token == nil {
            isLoading = false
            isConnected = false
            passwordRequired = true
            return
        }
        
        isConnected = true
        // Load data in parallel
        async let convos: () = loadConversations(vault: vault)
        async let starts: () = loadStarters(vault: vault)
        _ = await (convos, starts)
    }

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
            self.isConnected = true
        } catch let error as AgentBackendClient.AgentBackendError {
            if case .unauthorized = error {
                print("[AgentConvos] ⚠️ Unauthorized error in loadConversations")
                self.passwordRequired = true
            } else {
                print("[AgentConvos] ❌ Failed to load conversations: \(error)")
                logger.error("Failed to load conversations: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
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
        } catch let error as AgentBackendClient.AgentBackendError {
            if case .unauthorized = error {
                print("[AgentConvos] ⚠️ Unauthorized error in loadStarters")
                self.isConnected = false
                self.passwordRequired = true
            } else {
                logger.warning("Failed to load starters, using fallback: \(error.localizedDescription)")
                starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
            }
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
        // Obsolete: We now verify actual token auth via checkAuthAndLoad
    }

    func signIn(vault: Vault, password: String) async {
        isLoading = true
        do {
            _ = try await authService.signIn(vault: vault, password: password)
            passwordRequired = false
            isConnected = true
            await checkAuthAndLoad(vault: vault)
        } catch {
            self.error = "Sign-in failed: \(error.localizedDescription)"
            isLoading = false
        }
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
