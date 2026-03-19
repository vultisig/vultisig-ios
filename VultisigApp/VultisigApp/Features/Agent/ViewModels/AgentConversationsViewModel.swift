//
//  AgentConversationsViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import OSLog

@MainActor
final class AgentConversationsViewModel: ObservableObject, AgentLogging {

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
    let logger = Logger(subsystem: "com.vultisig", category: "AgentConversationsVM")

    private var startersRefreshTimer: Timer?
    private var lastStartersRefresh: Date?

    /// Generation token — incremented on disconnect to invalidate in-flight loaders.
    private var loadGeneration: Int = 0

    // MARK: - Load Conversations

    func checkAuthAndLoad(vault: Vault) async {
        isLoading = true
        let gen = loadGeneration
        let token = await getValidToken(vault: vault)

        guard gen == loadGeneration else { return }  // disconnected while awaiting

        if token == nil {
            isLoading = false
            isConnected = false
            passwordRequired = true
            return
        }

        isConnected = true
        // Load data in parallel, passing the already-fetched token to avoid re-fetching
        async let convos: () = loadConversations(vault: vault, prefetchedToken: token)
        async let starts: () = loadStarters(vault: vault, prefetchedToken: token)
        _ = await (convos, starts)
    }

    func loadConversations(vault: Vault, prefetchedToken: AgentAuthToken? = nil) async {
        let gen = loadGeneration
        let token: AgentAuthToken?
        if let t = prefetchedToken {
            token = t
        } else {
            token = await getValidToken(vault: vault)
        }
        guard gen == loadGeneration else { return }
        debugLog("[AgentConvos] Loading conversations with \(token != nil ? "available" : "missing") token")

        guard let token else {
            isLoading = false
            passwordRequired = true
            return
        }

        isLoading = true
        error = nil

        do {
            let response = try await backendClient.listConversations(
                publicKey: vault.pubKeyECDSA,
                skip: 0,
                take: 50,
                token: token.token
            )
            guard gen == loadGeneration else { return }
            conversations = response.conversations
            debugLog("[AgentConvos] Loaded \(response.conversations.count) conversations")
            logger.info("Loaded \(response.conversations.count) conversations")
            self.isConnected = true
        } catch let error as AgentBackendClient.AgentBackendError {
            guard gen == loadGeneration else { return }
            if case .unauthorized = error {
                self.passwordRequired = true
            } else {
                logger.error("Failed to load conversations: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
        } catch {
            guard gen == loadGeneration else { return }
            logger.error("Failed to load conversations: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Load Starters

    func loadStarters(vault: Vault, prefetchedToken: AgentAuthToken? = nil) async {
        // Refresh every 30 minutes
        if let lastRefresh = lastStartersRefresh,
           Date().timeIntervalSince(lastRefresh) < 30 * 60,
           !starters.isEmpty {
            return
        }

        let gen = loadGeneration
        let token: AgentAuthToken?
        if let t = prefetchedToken {
            token = t
        } else {
            token = await getValidToken(vault: vault)
        }
        guard gen == loadGeneration else { return }
        guard let token else {
            self.isConnected = false
            self.passwordRequired = true
            return
        }

        do {
            let context = AgentContextBuilder.buildContext(vault: vault)
            let request = AgentGetStartersRequest(
                publicKey: vault.pubKeyECDSA,
                context: context
            )

            let response = try await backendClient.getStarters(
                request: request,
                token: token.token
            )
            guard gen == loadGeneration else { return }

            if response.starters.isEmpty {
                starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
            } else {
                starters = Array(response.starters.shuffled().prefix(4))
            }

            lastStartersRefresh = Date()
        } catch let error as AgentBackendClient.AgentBackendError {
            guard gen == loadGeneration else { return }
            if case .unauthorized = error {
                self.isConnected = false
                self.passwordRequired = true
            } else {
                logger.warning("Failed to load starters, using fallback: \(error.localizedDescription)")
                starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
            }
        } catch {
            guard gen == loadGeneration else { return }
            logger.warning("Failed to load starters, using fallback: \(error.localizedDescription)")
            starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
        }
    }

    // MARK: - Create Conversation

    func createConversation(vault: Vault) async -> String? {
        guard let token = await getValidToken(vault: vault) else {
            passwordRequired = true
            return nil
        }

        do {
            let conv = try await backendClient.createConversation(
                publicKey: vault.pubKeyECDSA,
                token: token.token
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
        guard let token = await getValidToken(vault: vault) else {
            passwordRequired = true
            return
        }

        do {
            try await backendClient.deleteConversation(
                id: id,
                publicKey: vault.pubKeyECDSA,
                token: token.token
            )
            conversations.removeAll { $0.id == id }
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func deleteAllConversations(vault: Vault) async {
        let all = conversations
        await withTaskGroup(of: Void.self) { group in
            for conv in all {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.deleteConversation(id: conv.id, vault: vault)
                }
            }
        }
    }

    // MARK: - Auth

    @discardableResult
    func signIn(vault: Vault, password: String) async -> String? {
        isLoading = true
        do {
            _ = try await authService.signIn(vault: vault, password: password)
            passwordRequired = false
            isConnected = true
            await checkAuthAndLoad(vault: vault)
            return nil
        } catch {
            isLoading = false
            return error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func getValidToken(vault: Vault) async -> AgentAuthToken? {
        if let token = authService.getCachedToken(vaultPubKey: vault.pubKeyECDSA) {
            return token
        }
        return await authService.refreshIfNeeded(vaultPubKey: vault.pubKeyECDSA)
    }

    func disconnect(vault: Vault) async {
        loadGeneration += 1  // Invalidate any in-flight loaders
        await authService.disconnect(vaultPubKey: vault.pubKeyECDSA)
        isConnected = false
        conversations = []
        starters = []
        // Don't set passwordRequired here — let checkAuthAndLoad() set it
        // on the next screen load when it finds no valid token.
        // Setting it here would immediately re-open the password sheet.
    }

    func dismissError() {
        error = nil
    }

    deinit {
        startersRefreshTimer?.invalidate()
    }
}
