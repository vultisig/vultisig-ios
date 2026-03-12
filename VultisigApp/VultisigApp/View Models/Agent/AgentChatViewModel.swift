//
//  AgentChatViewModel.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-02-25.
//

import Foundation
import OSLog
import SwiftUI

@MainActor
final class AgentChatViewModel: ObservableObject, AgentLogging {

    // MARK: - Published State

    @Published var messages: [AgentChatMessage] = []
    @Published var starters: [String] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var conversationTitle: String?
    @Published var passwordRequired = false
    @Published var isConnected = false

    @Published var pendingSendTx: SendTransaction?
    @Published var pendingSwapTx: SwapTransaction?
    @Published var shouldShowPairingSheet = false
    @Published var showFastVaultPasswordPrompt = false
    @Published var activeKeysignPayload: KeysignPayload?
    var activeSignTxCallId: String?

    // MARK: - Private

    private let backendClient = AgentBackendClient()
    private let authService = AgentAuthService.shared
    let logger = Logger(subsystem: "com.vultisig", category: "AgentChatViewModel")
    private var currentTask: Task<Void, Never>?
    private var pendingMessage: String?
    internal var cachedFastVaultPassword: String?
    private var passwordClearTimer: Timer?

    private(set) lazy var streamManager = AgentStreamManager(viewModel: self)
    private(set) lazy var transactionBuilder = AgentTransactionBuilder(viewModel: self)
    private(set) lazy var keysignCoordinator = AgentKeysignCoordinator(viewModel: self)

    var conversationId: String?

    // MARK: - Hardcoded Fallback Starters

    static let fallbackStarters = [
        "What's my portfolio value?",
        "Show me my balances",
        "What's the price of ETH?",
        "Swap 0.01 ETH for USDC",
        "Check my Bitcoin balance",
        "List my vault chains",
        "What tokens do I have?",
        "Show my transaction history"
    ]

    // MARK: - Send Message

    func sendMessage(_ text: String, vault: Vault) {
        debugLog("[AgentChat] sendMessage called")

        // Add user message to UI
        let userMsg = AgentChatMessage(
            id: "msg-\(Date().timeIntervalSince1970)",
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMsg)
        isLoading = true
        error = nil
        streamManager.reset()

        currentTask = Task {
            guard let token = await requireAccessToken(vault: vault) else {
                warningLog("[AgentChat] No valid token available, prompting for password")
                await MainActor.run {
                    self.pendingMessage = text
                    self.passwordRequired = true
                    self.isLoading = false
                    // Remove the user message from the UI since it hasn't sent yet, we'll append it when it actually sends
                    self.messages.removeAll { $0.id == userMsg.id }
                }
                return
            }

            debugLog("[AgentChat] Using validated agent token")

            await executeSendMessage(text: text, vault: vault, token: token)
        }
    }

    private func executeSendMessage(text: String, vault: Vault, token: String) async {
        do {
            // Create conversation if needed
            if conversationId == nil {
                debugLog("[AgentChat] Creating new conversation")
                let conv = try await backendClient.createConversation(
                    publicKey: vault.pubKeyECDSA,
                    token: token
                )
                conversationId = conv.id
                debugLog("[AgentChat] Conversation created: \(conv.id)")

                await primeMCPSession(vault: vault, token: token, convId: conv.id)
            }

            // Fetch starters if needed
            if messages.isEmpty && starters.isEmpty {
                await loadStarters(vault: vault)
            }

            guard let convId = conversationId else {
                errorLog("[AgentChat] Conversation ID is missing after creation")
                throw AgentBackendClient.AgentBackendError.noBody
            }

            // Build context (full context on first message, light on subsequent)
            let context: AgentMessageContext
            if messages.count <= 2 {
                context = AgentContextBuilder.buildContext(vault: vault)  // @MainActor, not async
            } else {
                context = AgentContextBuilder.buildLightContext(vault: vault)  // @MainActor, not async
            }
            debugLog("[AgentChat] Built \(messages.count <= 2 ? "full" : "light") context")

            let request = AgentSendMessageRequest(
                publicKey: vault.pubKeyECDSA,
                content: text,
                model: "anthropic/claude-sonnet-4.5",
                context: context
            )

            if let data = try? JSONEncoder().encode(request) {
                debugLog("[AgentChat] Outgoing request payload encoded (\(data.count) bytes)")
            }

            // Stream the response
            debugLog("[AgentChat] Starting SSE stream for conversation \(convId)")
            let stream = backendClient.sendMessageStream(
                convId: convId,
                request: request,
                token: token
            )

            var eventCount = 0
            for try await event in stream {
                if Task.isCancelled {
                    warningLog("[AgentChat] Stream task was cancelled")
                    break
                }
                eventCount += 1
                debugLog("[AgentChat] Received SSE event #\(eventCount)")
                handleSSEEvent(event, vault: vault)
            }
            debugLog("[AgentChat] Stream ended after \(eventCount) events")

            isLoading = false

        } catch let error as AgentBackendClient.AgentBackendError {
            errorLog("[AgentChat] Backend error: \(error.localizedDescription)")
            handleError(error)
        } catch {
            errorLog("[AgentChat] General error: \(error.localizedDescription)")
            handleError(error)
        }
    }

    // MARK: - Send Action Result

    func sendActionResult(_ result: AgentActionResult, vault: Vault) {
        guard let convId = conversationId else { return }

        isLoading = true

        currentTask = Task {
            do {
                guard let token = await requireAccessToken(vault: vault) else {
                    streamManager.discardPendingStreamingSeedMessage()
                    isLoading = false
                    return
                }

                let request = AgentSendMessageRequest(
                    publicKey: vault.pubKeyECDSA,
                    model: "anthropic/claude-sonnet-4.5",
                    actionResult: result
                )

                let stream = backendClient.sendMessageStream(
                    convId: convId,
                    request: request,
                    token: token
                )

                for try await event in stream {
                    if Task.isCancelled { break }
                    handleSSEEvent(event, vault: vault)
                }

                isLoading = false

            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - Load Existing Conversation

    func loadConversation(id: String, vault: Vault) async {
        conversationId = id
        isLoading = true

        do {
            guard let token = await requireAccessToken(vault: vault) else {
                isLoading = false
                return
            }

            let conv = try await backendClient.getConversation(
                id: id,
                publicKey: vault.pubKeyECDSA,
                token: token
            )

            conversationTitle = conv.title

            await primeMCPSession(vault: vault, token: token, convId: id)

            // Convert backend messages to chat messages, filtering out internal
            // action-result echoes (e.g. "[Action result: Refresh Balances ...]")
            // that are only useful for backend context, not user display.
            messages = conv.messages.compactMap { msg in
                if msg.content.hasPrefix("[Action result:") { return nil }
                return AgentChatMessage(
                    id: msg.id,
                    role: msg.role == "user" ? .user : .assistant,
                    content: msg.content,
                    timestamp: AgentBackendClient.parseISO8601(msg.createdAt) ?? Date()
                )
            }

            isLoading = false
        } catch {
            handleError(error)
        }
    }

    // MARK: - Auth

    @discardableResult
    func signIn(vault: Vault, password: String) async -> String? {
        debugLog("[AgentChat] signIn called")
        do {
            _ = try await authService.signIn(vault: vault, password: password)
            debugLog("[AgentChat] signIn succeeded")
            isConnected = true
            passwordRequired = false
            cachedFastVaultPassword = password  // Cache for headless keysign reuse
            schedulePasswordClear()

            if let pending = pendingMessage {
                debugLog("[AgentChat] Sending pending message after login")
                let msgToSend = pending
                pendingMessage = nil
                self.sendMessage(msgToSend, vault: vault)
            }
            return nil
        } catch {
            errorLog("[AgentChat] signIn failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    func checkConnection(vault _: Vault) {
        // Agent backend uses public_key for identity, no auth token needed
        debugLog("[AgentChat] checkConnection reports connected for public_key auth")
        isConnected = true
    }

    // MARK: - Load Starters

    func loadStarters(vault: Vault) async {
        guard let token = await requireAccessToken(vault: vault) else {
            starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
            return
        }

        do {
            let context = AgentContextBuilder.buildContext(vault: vault)  // @MainActor, not async
            let request = AgentGetStartersRequest(
                publicKey: vault.pubKeyECDSA,
                context: context
            )

            let response = try await backendClient.getStarters(
                request: request,
                token: token
            )

            if response.starters.isEmpty {
                starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
            } else {
                starters = Array(response.starters.shuffled().prefix(4))
            }
            isConnected = true
        } catch let error as AgentBackendClient.AgentBackendError {
            if case .unauthorized = error {
                isConnected = false
                passwordRequired = true
            } else {
                logger.warning("Failed to load starters, using fallback: \(error.localizedDescription)")
            }
            starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
        } catch {
            logger.warning("Failed to load starters, using fallback: \(error.localizedDescription)")
            starters = Array(AgentChatViewModel.fallbackStarters.shuffled().prefix(4))
        }
    }

    func disconnect(vault: Vault) async {
        await authService.disconnect(vaultPubKey: vault.pubKeyECDSA)
        clearCachedPassword()
        isConnected = false
    }

    // MARK: - Cancel

    func cancelRequest() {
        streamManager.cancel()
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }

    // MARK: - Password Lifecycle

    /// Auto-clear the cached Fast Vault password after a bounded window (5 min).
    /// Limits secret lifetime in process memory across crashes, snapshots, etc.
    internal func schedulePasswordClear() {
        passwordClearTimer?.invalidate()
        passwordClearTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.clearCachedPassword() }
        }
    }

    private func clearCachedPassword() {
        cachedFastVaultPassword = nil
        passwordClearTimer?.invalidate()
        passwordClearTimer = nil
    }

    func dismissError() {
        error = nil
    }

    // MARK: - Delete Conversation

    @Published var conversationDeleted = false

    func deleteCurrentConversation(vault: Vault) {
        guard let convId = conversationId else { return }
        Task {
            guard let token = await requireAccessToken(vault: vault) else {
                return
            }
            do {
                try await backendClient.deleteConversation(
                    id: convId,
                    publicKey: vault.pubKeyECDSA,
                    token: token
                )
                conversationDeleted = true
            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - Feedback

    func submitFeedback(category: String, details: String, vault: Vault) async {
        guard let token = await requireAccessToken(vault: vault) else { return }
        let request = AgentFeedbackRequest(
            category: category,
            details: details,
            conversationId: conversationId
        )
        do {
            try await backendClient.submitFeedback(request: request, token: token)
        } catch {
            handleError(error)
        }
    }

    // MARK: - SSE Event Handling

    private func handleSSEEvent(_ event: AgentSSEEvent, vault: Vault? = nil) {
        streamManager.handleSSEEvent(event, vault: vault)
    }

    internal func handleActions(_ actions: [AgentBackendAction], vault: Vault) {
        var autoExecuteActions: [AgentBackendAction] = []

        for action in actions {
            // Add tool call status message
            let toolCallMsg = AgentChatMessage(
                id: "tool-call-\(action.id)",
                role: .assistant,
                content: "",
                timestamp: Date(),
                toolCall: AgentToolCallInfo(
                    actionType: action.type,
                    title: formatActionTitle(action.type, title: action.title),
                    params: action.params,
                    status: .running
                )
            )
            messages.append(toolCallMsg)

            if action.type == "build_send_tx" {
                transactionBuilder.createPendingSendTx(from: action.params, vault: vault)
            } else if action.type == "build_swap_tx" {
                // Like Windows: auto-execute locally — build keysign payload, store, report
                transactionBuilder.buildSwapTxAsync(action: action, vault: vault)
                continue // Skip auto-execute — we handle it ourselves
            } else if action.type == "sign_tx" {
                self.activeSignTxCallId = "tool-call-\(action.id)"
                keysignCoordinator.confirmSignTx(vault: vault)
            }

            if action.autoExecute {
                autoExecuteActions.append(action)
            }
        }

        // Execute all auto-execute actions
        if !autoExecuteActions.isEmpty {
            if autoExecuteActions.count == 1 {
                handleAutoExecuteAction(autoExecuteActions[0], vault: vault)
            } else {
                handleAutoExecuteActions(autoExecuteActions, vault: vault)
            }
        }
    }

    internal func handleAutoExecuteAction(_ action: AgentBackendAction, vault: Vault) {
        let toolCallId = "tool-call-\(action.id)"

        Task { @MainActor in
            let result = await AgentToolExecutor.execute(action: action, vault: vault)

            if let idx = self.messages.firstIndex(where: { $0.id == toolCallId }) {
                self.messages[idx].toolCall?.status = result.success ? .success : .error
                self.messages[idx].toolCall?.resultData = result.data
                self.messages[idx].toolCall?.error = result.error
            }

            // Plant a seed message marked isStreaming: true before streaming the result back
            self.isLoading = true
            let seedId = "streaming-\(Date().timeIntervalSince1970)"
            streamManager.setStreamingMessageId(seedId)
            self.messages.append(AgentChatMessage(
                id: seedId,
                role: .assistant,
                content: "",
                timestamp: Date(),
                isStreaming: true    // Bug fix: must be true so view and handleTextDelta handle this correctly
            ))

            // Stream the result back
            self.sendActionResult(result, vault: vault)
        }
    }

    internal func handleAutoExecuteActions(_ actions: [AgentBackendAction], vault: Vault) {
        // Execute all actions locally (no backend round-trip per action), then
        // send a SINGLE aggregated action result. This prevents N×backend calls
        // (e.g. "remove all 22 chains" becomes 1 request instead of 22).
        Task { @MainActor in
            var allSucceeded = true
            var aggregatedData: [String: AnyCodable] = [:]
            var errors: [String] = []
            let actionType = actions.first?.type ?? "batch"

            for action in actions {
                if Task.isCancelled { break }

                let toolCallId = "tool-call-\(action.id)"
                let result = await AgentToolExecutor.execute(action: action, vault: vault)

                if let idx = self.messages.firstIndex(where: { $0.id == toolCallId }) {
                    self.messages[idx].toolCall?.status = result.success ? .success : .error
                    self.messages[idx].toolCall?.resultData = result.data
                    self.messages[idx].toolCall?.error = result.error
                }

                if !result.success {
                    allSucceeded = false
                    errors.append(result.error ?? "unknown error for action \(action.id)")
                }

                if let outData = result.data {
                    for (k, v) in outData {
                        aggregatedData["\(action.id)_\(k)"] = v
                    }
                }
            }

            // Send ONE aggregated result back to the backend
            var summaryData: [String: AnyCodable] = [
                "completed": AnyCodable(actions.count),
                "succeeded": AnyCodable(allSucceeded ? actions.count : actions.count - errors.count),
                "failed": AnyCodable(errors.count)
            ]
            if !aggregatedData.isEmpty {
                summaryData["results"] = AnyCodable(aggregatedData)
            }
            if !errors.isEmpty {
                summaryData["errors"] = AnyCodable(errors)
            }

            let aggregatedResult = AgentActionResult(
                action: actionType,
                success: allSucceeded,
                data: summaryData,
                error: errors.isEmpty ? nil : errors.joined(separator: "; ")
            )

            // Plant an empty "seed" assistant message and register it as the
            // current streaming message BEFORE calling sendActionResult.
            await MainActor.run {
                self.isLoading = true
                let seedId = "streaming-\(Date().timeIntervalSince1970)"
                streamManager.setStreamingMessageId(seedId)
                self.messages.append(AgentChatMessage(
                    id: seedId,
                    role: .assistant,
                    content: "",
                    timestamp: Date(),
                    isStreaming: true    // Bug fix: must be true so view and handleTextDelta handle this correctly
                ))
            }
            self.sendActionResult(aggregatedResult, vault: vault)
        }
    }

    internal func handleTxReady(_ txReady: AgentTxReady) {
        let msg = AgentChatMessage(
            id: "tx-proposal-\(Date().timeIntervalSince1970)",
            role: .assistant,
            content: "",
            timestamp: Date(),
            txProposal: txReady
        )
        messages.append(msg)
        isLoading = false
    }

    func acceptTxProposal(_ proposal: AgentTxReady, vault: Vault) {
        debugLog("[AgentChat] User accepted transaction proposal")
        let approvedMsg = AgentChatMessage(
            id: "tx-approved-\(Date().timeIntervalSince1970)",
            role: .assistant,
            content: "",
            timestamp: Date(),
            txStatus: AgentTxStatusInfo(
                txHash: "",
                chain: proposal.fromChain,
                status: .confirmed,
                label: "agentTransactionApproved".localized
            )
        )
        messages.append(approvedMsg)

        // 1. Find the source coin in the vault
        guard let coin = vault.coins.first(where: {
            $0.chain.name.lowercased() == proposal.fromChain.lowercased() &&
            $0.ticker.lowercased() == proposal.fromSymbol.lowercased()
        }) else {
            warningLog("[AgentChat] Coin \(proposal.fromSymbol) on \(proposal.fromChain) not found in vault")
            self.error = "Coin \(proposal.fromSymbol) on \(proposal.fromChain) not found in vault."
            isLoading = false
            return
        }

        // 2. Create a SendTransaction so the pairing/keysign sheets have context
        let tx = SendTransaction()
        tx.coin = coin
        tx.fromAddress = proposal.sender
        tx.toAddress = proposal.destination
        let localizedAmount = proposal.amount.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
        tx.amount = localizedAmount
        tx.vault = vault
        self.pendingSendTx = tx

        // 3. Decode the pre-built keysign payload from the backend
        guard let payloadString = proposal.keysignPayload,
              let payloadData = payloadString.data(using: .utf8) else {
            warningLog("[AgentChat] Missing or invalid keysignPayload in tx_ready")
            self.error = "Missing keysign payload from backend."
            isLoading = false
            return
        }

        do {
            let payload = try JSONDecoder().decode(KeysignPayload.self, from: payloadData)
            self.activeKeysignPayload = payload
            debugLog("[AgentChat] Decoded keysign payload for swap: \(coin.ticker) on \(coin.chain.name)")

            // 4. Trigger keysign — same logic as confirmSignTx
            if vault.isFastVault {
                if let password = cachedFastVaultPassword, !password.isEmpty {
                    debugLog("[AgentChat] Using cached FastVault password for swap keysign")
                    keysignCoordinator.executeFastVaultKeysign(password: password, vault: vault)
                } else {
                    debugLog("[AgentChat] FastVault password not cached, showing prompt for swap")
                    self.showFastVaultPasswordPrompt = true
                }
            } else {
                self.shouldShowPairingSheet = true
            }
        } catch {
            warningLog("[AgentChat] Failed to decode keysign payload: \(error.localizedDescription)")
            self.error = "Failed to decode swap keysign payload: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func rejectTxProposal(_: AgentTxReady, vault: Vault) {
        debugLog("[AgentChat] User rejected transaction proposal")
        sendMessage("Cancel the transaction. I do not want to execute it.", vault: vault)
    }

    func handleTxBroadcasted(txid: String, vault: Vault) {
        keysignCoordinator.handleTxBroadcasted(txid: txid, vault: vault)
    }

    func executeFastVaultKeysign(password: String, vault: Vault) {
        keysignCoordinator.executeFastVaultKeysign(password: password, vault: vault)
    }

    internal func appendAssistantMessage(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let msg = AgentChatMessage(
            id: "msg-\(Date().timeIntervalSince1970)",
            role: .assistant,
            content: content,
            timestamp: Date()
        )
        messages.append(msg)
    }

    // MARK: - Helpers

    private func primeMCPSession(vault: Vault, token: String, convId: String) async {
        debugLog("[AgentChat] Priming backend MCP session with set_vault")
        let setVaultResult = AgentActionResult(
            action: "set_vault",
            success: true,
            data: [
                "ecdsa_public_key": AnyCodable(vault.pubKeyECDSA),
                "eddsa_public_key": AnyCodable(vault.pubKeyEdDSA),
                "chain_code": AnyCodable(vault.hexChainCode)
            ]
        )
        let primeRequest = AgentSendMessageRequest(
            publicKey: vault.pubKeyECDSA,
            model: "anthropic/claude-sonnet-4.5",
            actionResult: setVaultResult
        )
        // Execute without streaming back to UI
        _ = try? await backendClient.sendMessage(convId: convId, request: primeRequest, token: token)
        debugLog("[AgentChat] MCP session primed")
    }

    private func getValidToken(vault: Vault) async -> AgentAuthToken? {
        debugLog("[AgentChat] Checking cached token")
        if let token = authService.getCachedToken(vaultPubKey: vault.pubKeyECDSA) {
            debugLog("[AgentChat] Found cached token")
            return token
        }
        debugLog("[AgentChat] No cached token, attempting refresh")
        let refreshed = await authService.refreshIfNeeded(vaultPubKey: vault.pubKeyECDSA)
        debugLog("[AgentChat] Token refresh result: \(refreshed != nil ? "found" : "none")")
        return refreshed
    }

    private func requireAccessToken(vault: Vault) async -> String? {
        guard let authToken = await getValidToken(vault: vault) else {
            passwordRequired = true
            isConnected = false
            return nil
        }

        let token = authToken.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            passwordRequired = true
            isConnected = false
            return nil
        }

        isConnected = true
        return token
    }

    private func handleError(_ error: Error) {
        warningLog("[AgentChat] handleError: \(error.localizedDescription)")
        streamManager.reset()
        isLoading = false

        if case AgentBackendClient.AgentBackendError.unauthorized = error {
            warningLog("[AgentChat] Unauthorized error, showing password prompt")
            passwordRequired = true
            self.error = nil
        } else {
            self.error = error.localizedDescription
        }

        logger.error("Agent error: \(error.localizedDescription)")
    }

    private func formatActionTitle(_ type: String, title: String) -> String {
        switch type {
        case "get_balances": return "FETCHING BALANCES"
        case "get_market_price": return "FETCHING PRICES"
        case "build_swap_tx": return "PREPARING SWAP"
        case "add_token": return "ADDING TOKEN"
        case "add_chain": return "ADDING CHAIN"
        case "get_address_book": return "CHECKING ADDRESS BOOK"
        case "add_address_book": return "UPDATING ADDRESS BOOK"
        default: return title.uppercased()
        }
    }

    internal func normalizeErrorMessage(_ error: String) -> String {
        let lower = error.lowercased()
        let cancelPatterns = ["context canceled", "context cancelled", "user cancelled", "user canceled", "agent stopped"]
        for pattern in cancelPatterns {
            if lower.contains(pattern) {
                return "agent stopped"
            }
        }
        return error
    }
}
