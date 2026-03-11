//
//  AgentTransactionBuilder.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2026-03-11.
//

import Foundation
import OSLog
import SwiftUI

@MainActor
final class AgentTransactionBuilder: AgentLogging {
    private weak var viewModel: AgentChatViewModel?
    let logger = Logger(subsystem: "com.vultisig", category: "AgentTransactionBuilder")

    init(viewModel: AgentChatViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Shared Helpers (used by AgentKeysignCoordinator too)

    /// Rebuild a swap keysign payload with a fresh DEX quote and blockhash.
    /// Extracted to avoid duplicating this 6-line sequence in three places.
    static func rebuildSwapPayload(swapTx: SwapTransaction, vault: Vault) async throws -> KeysignPayload {
        let logic = SwapCryptoLogic()
        await BalanceService.shared.updateBalance(for: swapTx.fromCoin)
        let quote = try await logic.fetchQuote(tx: swapTx, vault: vault, referredCode: "")
        swapTx.quote = quote
        let chainSpecific = try await logic.fetchChainSpecific(tx: swapTx)
        swapTx.gas = chainSpecific.gas
        swapTx.thorchainFee = try await logic.thorchainFee(for: chainSpecific, tx: swapTx, vault: vault)
        return try await logic.buildSwapKeysignPayload(tx: swapTx, vault: vault)
    }

    /// Rebuild a send keysign payload with fresh fee estimation and balance validation.
    static func rebuildSendPayload(sendTx: SendTransaction, vault: Vault) async throws -> KeysignPayload {
        let logic = SendCryptoVerifyLogic()
        await BalanceService.shared.updateBalance(for: sendTx.coin)
        let feeResult = try await logic.calculateFee(tx: sendTx)
        sendTx.fee = feeResult.fee
        sendTx.gas = feeResult.gas
        let validation = logic.validateBalanceWithFee(tx: sendTx)
        if !validation.isValid {
            let errStr = validation.errorMessage ?? "Insufficient balance to cover fee."
            let localizedErr = NSLocalizedString(errStr, comment: "")
            throw HelperError.runtimeError(localizedErr == errStr ? errStr : localizedErr)
        }
        try await logic.validateUtxosIfNeeded(tx: sendTx)
        return try await logic.buildKeysignPayload(tx: sendTx, vault: vault)
    }

    /// Resolve from/to coins and human-readable amount from backend swap params.
    /// Throws a specific parse error when required params or coins are missing.
    struct SwapParseResult {
        let fromCoin: Coin
        let toCoin: Coin
        let humanAmount: String
        let localizedAmount: String
    }

    enum SwapParseError: LocalizedError {
        case missingFromChain
        case sourceCoinNotFound(symbol: String, chain: String)
        case destinationCoinNotFound(symbol: String, chain: String)

        var errorDescription: String? {
            switch self {
            case .missingFromChain:
                return "missing from_chain param"
            case .sourceCoinNotFound(let symbol, let chain):
                return "source coin \(symbol) on \(chain) not found in vault"
            case .destinationCoinNotFound(let symbol, let chain):
                return "destination coin \(symbol) on \(chain) not found in vault"
            }
        }
    }

    static func parseSwapParams(_ params: [String: AnyCodable], vault: Vault) throws -> SwapParseResult {
        guard let fromChain = params["from_chain"]?.value as? String else {
            throw SwapParseError.missingFromChain
        }

        let fromSymbol = (params["from_symbol"]?.value as? String)
            ?? (params["from_ticker"]?.value as? String) ?? ""
        let toChain = (params["to_chain"]?.value as? String) ?? fromChain
        let toSymbol = (params["to_symbol"]?.value as? String)
            ?? (params["to_ticker"]?.value as? String) ?? ""

        guard let fromCoin = vault.coins.first(where: {
            $0.chain.name.lowercased() == fromChain.lowercased() &&
            (fromSymbol.isEmpty || $0.ticker.lowercased() == fromSymbol.lowercased())
        }) else {
            throw SwapParseError.sourceCoinNotFound(symbol: fromSymbol, chain: fromChain)
        }

        let toContract = params["to_contract"]?.value as? String
        let toCoin: Coin
        if let found = vault.coins.first(where: {
            $0.chain.name.lowercased() == toChain.lowercased() &&
            (toSymbol.isEmpty || $0.ticker.lowercased() == toSymbol.lowercased())
        }) {
            toCoin = found
        } else if let contract = toContract, !contract.isEmpty,
                  let found = vault.coins.first(where: {
                      $0.contractAddress.lowercased() == contract.lowercased()
                  }) {
            toCoin = found
        } else {
            throw SwapParseError.destinationCoinNotFound(symbol: toSymbol, chain: toChain)
        }

        let humanAmount: String
        if let rawAmount = params["amount"]?.value as? String {
            let decimals = (params["from_decimals"]?.value as? Int) ?? fromCoin.decimals
            if let baseValue = Decimal(string: rawAmount), decimals > 0 {
                humanAmount = "\(baseValue / pow(Decimal(10), decimals))"
            } else {
                humanAmount = rawAmount
            }
        } else {
            humanAmount = "0"
        }

        let localizedAmount = humanAmount.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
        return SwapParseResult(fromCoin: fromCoin, toCoin: toCoin, humanAmount: humanAmount, localizedAmount: localizedAmount)
    }

    private static func makeSwapTransaction(parsed: SwapParseResult, vault: Vault) -> SwapTransaction {
        let swapTx = SwapTransaction()
        swapTx.fromCoin = parsed.fromCoin
        swapTx.toCoin = parsed.toCoin
        swapTx.fromCoins = vault.coins
        swapTx.toCoins = vault.coins
        swapTx.fromAmount = parsed.localizedAmount
        return swapTx
    }

    private static func makeSendContextTransaction(
        parsed: SwapParseResult,
        vault: Vault,
        toAddress: String,
        memo: String = ""
    ) -> SendTransaction {
        let sendTx = SendTransaction()
        sendTx.coin = parsed.fromCoin
        sendTx.fromAddress = parsed.fromCoin.address
        sendTx.toAddress = toAddress
        sendTx.amount = parsed.localizedAmount
        sendTx.memo = memo
        sendTx.vault = vault
        return sendTx
    }

    func createPendingSendTx(from params: [String: AnyCodable]?, vault: Vault) {
        debugLog("[AgentChat] createPendingSendTx called with \(params != nil ? "present" : "missing") params")
        guard let viewModel = viewModel else { return }
        guard let params = params,
              let chainStr = params["chain"]?.value as? String,
              let symbolStr = params["symbol"]?.value as? String,
              let amountStr = params["amount"]?.value as? String,
              let addressStr = params["address"]?.value as? String else {
            warningLog("[AgentChat] createPendingSendTx is missing required params")
            return
        }

        debugLog("[AgentChat] Preparing pending send tx for \(symbolStr) on \(chainStr)")

        // Find coin in vault
        if let coin = vault.coins.first(where: {
            $0.chain.name.lowercased() == chainStr.lowercased() &&
            $0.ticker.lowercased() == symbolStr.lowercased()
        }) {
            let tx = SendTransaction()
            tx.coin = coin
            tx.fromAddress = coin.address
            tx.toAddress = addressStr
            let localizedAmount = amountStr.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
            tx.amount = localizedAmount
            tx.vault = vault // Explicitly assign Vault to allow isFastVault detection

            if let memoStr = params["memo"]?.value as? String {
                tx.memo = memoStr
            }

            viewModel.pendingSendTx = tx
            debugLog("[AgentChat] Pending send tx prepared for \(coin.ticker) on \(coin.chain.name)")
        } else {
            warningLog("[AgentChat] Coin \(symbolStr) on \(chainStr) was not found in the current vault")
        }
    }

    /// Creates a `SwapTransaction` from `build_swap_tx` action params.
    /// Uses the app's existing swap infrastructure (SwapCryptoLogic) to fetch
    /// quotes and build keysign payloads — supports THORChain, Jupiter, 1inch, etc.
    func createPendingSwapTx(from params: [String: AnyCodable]?, vault: Vault) {
        debugLog("[AgentChat] createPendingSwapTx called with \(params != nil ? "present" : "missing") params")
        guard let viewModel = viewModel else { return }
        guard let params = params else {
            warningLog("[AgentChat] createPendingSwapTx is missing params")
            return
        }

        do {
            let parsed = try Self.parseSwapParams(params, vault: vault)
            viewModel.pendingSwapTx = Self.makeSwapTransaction(parsed: parsed, vault: vault)
            viewModel.pendingSendTx = Self.makeSendContextTransaction(
                parsed: parsed,
                vault: vault,
                toAddress: parsed.fromCoin.address
            )
            debugLog("[AgentChat] Pending swap tx prepared: \(parsed.fromCoin.ticker) → \(parsed.toCoin.ticker), amount=\(parsed.humanAmount)")
        } catch {
            warningLog("[AgentChat] createPendingSwapTx failed: \(error.localizedDescription)")
        }
    }

    /// Mirrors Windows `buildTxAsync` flow: auto-execute `build_swap_tx` locally,
    /// build keysign payload via SwapCryptoLogic, store it, and report result to backend.
    func buildSwapTxAsync(action: AgentBackendAction, vault: Vault) {
        guard let viewModel = viewModel else { return }
        Task {
            do {
                let params = action.params ?? [:]
                let parsed = try Self.parseSwapParams(params, vault: vault)
                let swapTx = Self.makeSwapTransaction(parsed: parsed, vault: vault)

                debugLog("[AgentChat] Building swap keysign payload: \(parsed.fromCoin.ticker) → \(parsed.toCoin.ticker), amount=\(parsed.humanAmount)")

                let keysignPayload = try await Self.rebuildSwapPayload(swapTx: swapTx, vault: vault)
                debugLog("[AgentChat] Swap keysign payload built successfully")

                await MainActor.run {
                    viewModel.activeKeysignPayload = keysignPayload
                    viewModel.pendingSwapTx = swapTx
                    viewModel.pendingSendTx = Self.makeSendContextTransaction(
                        parsed: parsed,
                        vault: vault,
                        toAddress: keysignPayload.toAddress,
                        memo: keysignPayload.memo ?? ""
                    )
                }

                let resultData: [String: AnyCodable] = [
                    "status": AnyCodable("ready"),
                    "from_chain": AnyCodable(parsed.fromCoin.chain.name),
                    "from_symbol": AnyCodable(parsed.fromCoin.ticker),
                    "to_chain": AnyCodable(parsed.toCoin.chain.name),
                    "to_symbol": AnyCodable(parsed.toCoin.ticker),
                    "amount": AnyCodable(parsed.humanAmount),
                    "sender": AnyCodable(parsed.fromCoin.address),
                    "destination": AnyCodable(keysignPayload.toAddress)
                ]
                let result = AgentActionResult(action: "build_swap_tx", actionId: action.id, success: true, data: resultData)
                viewModel.sendActionResult(result, vault: vault)

            } catch let error as SwapParseError {
                warningLog("[AgentChat] buildSwapTxAsync failed: \(error.localizedDescription)")
                let result = AgentActionResult(action: "build_swap_tx", actionId: action.id, success: false, error: error.localizedDescription)
                viewModel.sendActionResult(result, vault: vault)
            } catch {
                errorLog("[AgentChat] buildSwapTxAsync failed: \(error.localizedDescription)")
                let result = AgentActionResult(action: "build_swap_tx", actionId: action.id, success: false, error: error.localizedDescription)
                viewModel.sendActionResult(result, vault: vault)
            }
        }
    }
}
