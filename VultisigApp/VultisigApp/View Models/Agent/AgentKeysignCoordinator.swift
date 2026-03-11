//
//  AgentKeysignCoordinator.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-03-11.
//

@preconcurrency import Foundation
import OSLog
import SwiftUI

@MainActor
final class AgentKeysignCoordinator: AgentLogging {
    private weak var viewModel: AgentChatViewModel?
    let logger = Logger(subsystem: "com.vultisig", category: "AgentKeysignCoordinator")

    init(viewModel: AgentChatViewModel) {
        self.viewModel = viewModel
    }

    func handleTxBroadcasted(txid: String, vault: Vault) {
        guard let viewModel = viewModel else { return }

        let callId = viewModel.activeSignTxCallId

        // Send the result to AI
        let result = AgentActionResult(
            action: "sign_tx",
            success: true,
            data: ["txid": AnyCodable(txid)]
        )

        MainActor.assumeIsolated {
            viewModel.shouldShowPairingSheet = false
            viewModel.pendingSendTx = nil
            viewModel.pendingSwapTx = nil
            viewModel.activeSignTxCallId = nil

            // Update the tool-call message bubble if we have a matching ID
            if let callId = callId, let idx = viewModel.messages.firstIndex(where: { $0.id == callId }) {
                viewModel.messages[idx].toolCall?.status = .success
                viewModel.messages[idx].toolCall?.resultData = ["txid": AnyCodable(txid)]
            }

            // Always append the txid to chat so it's visible to the user
            viewModel.appendAssistantMessage(String(format: "agentTransactionBroadcast".localized, txid))

            viewModel.sendActionResult(result, vault: vault)
        }
    }

    func confirmSignTx(vault: Vault) {
        guard let viewModel = viewModel else { return }
        debugLog("[AgentChat] confirmSignTx called")

        // We intentionally DO NOT reuse `activeKeysignPayload` here for swaps.
        // Solana's blockhash expires quickly, and DEX quotes expire too.
        // We must rebuild the payload right before signing to get a fresh blockhash and quote.

        guard let pendingSendTx = viewModel.pendingSendTx else {
            warningLog("[AgentChat] confirmSignTx aborted because pendingSendTx is nil")
            let result = AgentActionResult(
                action: "sign_tx",
                actionId: viewModel.activeSignTxCallId?.replacingOccurrences(of: "tool-call-", with: ""),
                success: false,
                error: "no_pending_transaction: the swap transaction was not prepared. Please resend build_swap_tx with address and memo params before sign_tx."
            )
            viewModel.sendActionResult(result, vault: vault)

            if let callId = viewModel.activeSignTxCallId,
               let idx = viewModel.messages.firstIndex(where: { $0.id == callId }) {
                viewModel.messages[idx].toolCall?.status = .error
                viewModel.messages[idx].toolCall?.error = "Transaction not ready"
            }
            viewModel.activeSignTxCallId = nil
            return
        }

        debugLog("[AgentChat] confirmSignTx continuing for \(pendingSendTx.coin.ticker) on \(pendingSendTx.coin.chain.name)")
        if vault.isFastVault {
            // FastVault: either use cached password or prompt — never fall to pairing sheet
            if let password = viewModel.cachedFastVaultPassword, !password.isEmpty {
                debugLog("[AgentChat] Using cached FastVault password for keysign")
                executeFastVaultKeysign(password: password, vault: vault)
            } else {
                debugLog("[AgentChat] FastVault password not cached, showing prompt")
                viewModel.showFastVaultPasswordPrompt = true
            }
        } else {
            Task {
                await MainActor.run {
                    viewModel.isLoading = true
                    viewModel.appendAssistantMessage("agentGeneratingKeysign".localized)
                }

                do {
                    let payload: KeysignPayload

                    if let swapTx = viewModel.pendingSwapTx {
                        debugLog("[AgentChat] Rebuilding swap keysign payload for fresh blockhash (Pairing)")
                        payload = try await AgentTransactionBuilder.rebuildSwapPayload(swapTx: swapTx, vault: vault)
                    } else {
                        payload = try await AgentTransactionBuilder.rebuildSendPayload(sendTx: pendingSendTx, vault: vault)
                    }

                    await MainActor.run {
                        viewModel.isLoading = false
                        viewModel.activeKeysignPayload = payload
                        viewModel.shouldShowPairingSheet = true
                    }
                } catch {
                    await MainActor.run {
                        viewModel.isLoading = false
                        viewModel.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func executeFastVaultKeysign(password: String, vault: Vault) {
        guard let viewModel = viewModel else { return }
        guard let tx = viewModel.pendingSendTx else {
            warningLog("[AgentChat] executeFastVaultKeysign aborted because pendingSendTx is nil")
            return
        }

        // Cache password for future transactions in this session
        if viewModel.cachedFastVaultPassword == nil {
            viewModel.cachedFastVaultPassword = password
            viewModel.schedulePasswordClear()
        }

        Task {
            await MainActor.run {
                viewModel.isLoading = true
                viewModel.appendAssistantMessage("agentSigningBroadcasting".localized)
            }

            do {
                let keysignPayload: KeysignPayload

                if let swapTx = viewModel.pendingSwapTx {
                    debugLog("[AgentChat] Rebuilding swap keysign payload for fresh blockhash (FastVault)")
                    keysignPayload = try await AgentTransactionBuilder.rebuildSwapPayload(swapTx: swapTx, vault: vault)
                } else {
                    debugLog("[AgentChat] Validating balance for fast vault transaction")
                    keysignPayload = try await AgentTransactionBuilder.rebuildSendPayload(sendTx: tx, vault: vault)
                }

                // 3. Generate Keysign Messages (Matches KeysignDiscoveryViewModel flow)
                let finalPayload = keysignPayload.coin.chain == .solana ?
                try await BlockChainService.shared.refreshSolanaBlockhash(for: keysignPayload) : keysignPayload
                let keysignFactory = KeysignMessageFactory(payload: finalPayload)
                let preSignedImageHash = try keysignFactory.getKeysignMessages()
                let keysignMessages = preSignedImageHash.sorted()

                guard !keysignMessages.isEmpty else {
                    throw HelperError.runtimeError("No message need to be signed")
                }

                // 4. FastVault Keysign execution
                let input = FastVaultKeysignInput(
                    vault: vault,
                    keysignMessages: keysignMessages,
                    derivePath: finalPayload.coin.coinType.derivationPath(),
                    isECDSA: finalPayload.coin.chain.signingKeyType == .ECDSA,
                    vaultPassword: password,
                    chain: finalPayload.coin.chain.name
                )

                let result = try await FastVaultKeysignService.shared.keysign(input: input)
                debugLog("[AgentChat] Keysign returned \(result.signatures.count) signature(s)")

                // 5. Broadcast Transaction
                await MainActor.run {
                    viewModel.appendAssistantMessage("agentTransactionSigned".localized)
                }

                let keysignViewModel = KeysignViewModel()
                keysignViewModel.vault = vault
                keysignViewModel.keysignPayload = finalPayload
                keysignViewModel.signatures = result.signatures

                debugLog("[AgentChat] Broadcasting signed transaction for \(finalPayload.coin.ticker) on \(finalPayload.coin.chain.name)")

                // For UTXO chains (DOGE, BTC, LTC, DASH, ZEC, BCH), broadcastTransaction()
                // uses a completion-handler internally, so the txid isn't set when the
                // async function returns. We wait for the NotificationCenter post instead,
                // with a 30-second timeout.
                let isUTXO = finalPayload.coin.chain.chainType == .UTXO

                if isUTXO {
                    // Start an async waitUntil-style listener before calling broadcast
                    let txid = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
                        var token: NSObjectProtocol?
                        var completed = false
                        token = NotificationCenter.default.addObserver(
                            forName: .agentDidBroadcastTx,
                            object: nil,
                            queue: .main
                        ) { notification in
                            guard !completed else { return }
                            completed = true
                            if let t = notification.userInfo?["txid"] as? String {
                                continuation.resume(returning: t)
                            } else {
                                continuation.resume(returning: "")
                            }
                            if let token { NotificationCenter.default.removeObserver(token) }
                        }

                        // Kick off broadcast AFTER registering listener
                        Task { @MainActor in
                            await keysignViewModel.broadcastTransaction()
                            debugLog("[AgentChat] UTXO broadcastTransaction() returned")

                            // If we already have a result (error path or immediate success), resume
                            if !completed {
                                if !keysignViewModel.keysignError.isEmpty {
                                    completed = true
                                    if let token { NotificationCenter.default.removeObserver(token) }
                                    continuation.resume(returning: "")
                                } else {
                                    // Schedule a 30-second timeout
                                    Task {
                                        try? await Task.sleep(for: .seconds(30))
                                        if !completed {
                                            completed = true
                                            warningLog("[AgentChat] UTXO broadcast timed out after 30 seconds")
                                            if let token { NotificationCenter.default.removeObserver(token) }
                                            continuation.resume(returning: "")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !txid.isEmpty {
                        debugLog("[AgentChat] UTXO broadcast succeeded")
                        self.handleTxBroadcasted(txid: txid, vault: vault)
                    } else if !keysignViewModel.keysignError.isEmpty {
                        errorLog("[AgentChat] Broadcast error: \(keysignViewModel.keysignError)")
                        throw HelperError.runtimeError(keysignViewModel.keysignError)
                    } else {
                        throw HelperError.runtimeError("Broadcast timed out or returned no txid. Check your balance and network, then try again.")
                    }
                } else {
                    // Non-UTXO chains set txid synchronously inside broadcastTransaction()
                    await keysignViewModel.broadcastTransaction()
                    debugLog("[AgentChat] Non-UTXO broadcastTransaction() finished")

                    if !keysignViewModel.txid.isEmpty {
                        debugLog("[AgentChat] Broadcast returned a txid")
                        self.handleTxBroadcasted(txid: keysignViewModel.txid, vault: vault)
                    } else if !keysignViewModel.keysignError.isEmpty {
                        errorLog("[AgentChat] Broadcast error from KeysignViewModel: \(keysignViewModel.keysignError)")
                        throw HelperError.runtimeError(keysignViewModel.keysignError)
                    } else {
                        errorLog("[AgentChat] Broadcast returned empty txid and empty keysignError")
                        throw HelperError.runtimeError("Broadcast completed but no txid or error returned. Check your balance and try again.")
                    }
                }
            } catch {
                errorLog("[AgentChat] executeFastVaultKeysign failed: \(error.localizedDescription)")
                await MainActor.run {
                    viewModel.isLoading = false
                    viewModel.appendAssistantMessage("❌ Error: \(error.localizedDescription)")
                    viewModel.error = error.localizedDescription
                }
            }
        }
    }
}
