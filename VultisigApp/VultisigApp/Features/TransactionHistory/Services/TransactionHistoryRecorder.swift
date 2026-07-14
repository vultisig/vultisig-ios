//
//  TransactionHistoryRecorder.swift
//  VultisigApp
//

import Foundation
import OSLog

@MainActor
final class TransactionHistoryRecorder {
    static let shared = TransactionHistoryRecorder()

    private let storage = TransactionHistoryStorage.shared
    private let logger = Logger(subsystem: "com.vultisig.app", category: "tx-history-recorder")

    private init() {}

    // MARK: - Record Send

    func recordSend(
        txHash: String,
        pubKeyECDSA: String,
        coin: Coin,
        amountCrypto: String,
        amountFiat: String,
        fromAddress: String,
        toAddress: String,
        feeCrypto: String,
        feeFiat: String,
        chain: Chain,
        explorerLink: String
    ) {
        let data = TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: pubKeyECDSA,
            type: .send,
            status: .inProgress,
            chainRawValue: chain.rawValue,
            coinTicker: coin.ticker,
            coinLogo: coin.logo,
            coinChainLogo: coin.tokenChainLogo,
            amountCrypto: amountCrypto,
            amountFiat: amountFiat,
            fromAddress: fromAddress,
            toAddress: toAddress,
            toCoinTicker: nil,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: nil,
            toAmountFiat: nil,
            swapProvider: nil,
            feeCrypto: feeCrypto,
            feeFiat: feeFiat,
            network: chain.name,
            explorerLink: explorerLink,
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: ChainStatusConfig.config(for: chain).estimatedTime,
            errorMessage: nil
        )
        do {
            try storage.save(data)
        } catch {
            logger.error("Save failed for txHash=\(txHash): \(error)")
        }
    }

    // MARK: - Record Swap

    /// Records a swap row.
    ///
    /// `swapTracking` is written in the SAME save as the row. Providers that
    /// only learn their tracking identifiers later (SwapKit, whose `attach`
    /// closure fires on done-screen appear) pass `nil` here and call
    /// `attachSwapTracking` afterwards. Providers that already know them at
    /// record time (THORChain limit orders) MUST pass them here instead: a
    /// row that is saved untracked and only tracked by a second save has a
    /// window where a failure leaves it permanently untracked — and an
    /// untracked limit row is exactly the row the native poller marks
    /// Successful while it is still resting.
    func recordSwap(
        txHash: String,
        approveTxHash: String?,
        pubKeyECDSA: String,
        fromCoin: Coin,
        toCoin: Coin,
        fromAmountCrypto: String,
        fromAmountFiat: String,
        toAmountCrypto: String,
        toAmountFiat: String,
        fromAddress: String,
        toAddress: String,
        feeCrypto: String,
        feeFiat: String,
        chain: Chain,
        explorerLink: String,
        provider: String?,
        swapTracking: SwapTrackingMetadataData? = nil
    ) {
        let data = TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: approveTxHash,
            pubKeyECDSA: pubKeyECDSA,
            type: .swap,
            status: .inProgress,
            chainRawValue: chain.rawValue,
            coinTicker: fromCoin.ticker,
            coinLogo: fromCoin.logo,
            coinChainLogo: fromCoin.tokenChainLogo,
            amountCrypto: fromAmountCrypto,
            amountFiat: fromAmountFiat,
            fromAddress: fromAddress,
            toAddress: toAddress,
            toCoinTicker: toCoin.ticker,
            toCoinLogo: toCoin.logo,
            toCoinChainLogo: toCoin.tokenChainLogo,
            toAmountCrypto: toAmountCrypto,
            toAmountFiat: toAmountFiat,
            swapProvider: provider,
            feeCrypto: feeCrypto,
            feeFiat: feeFiat,
            network: chain.name,
            explorerLink: explorerLink,
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: ChainStatusConfig.config(for: chain).estimatedTime,
            errorMessage: nil,
            swapTracking: swapTracking
        )
        do {
            try storage.save(data)
        } catch {
            logger.error("Save failed for txHash=\(txHash): \(error)")
        }
    }

    // MARK: - Record Approve

    func recordApprove(
        txHash: String,
        pubKeyECDSA: String,
        coin: Coin,
        amountCrypto: String,
        spender: String,
        chain: Chain,
        explorerLink: String
    ) {
        let data = TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: pubKeyECDSA,
            type: .approve,
            status: .inProgress,
            chainRawValue: chain.rawValue,
            coinTicker: coin.ticker,
            coinLogo: coin.logo,
            coinChainLogo: coin.tokenChainLogo,
            amountCrypto: amountCrypto,
            amountFiat: "",
            fromAddress: coin.address,
            toAddress: spender,
            toCoinTicker: nil,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: nil,
            toAmountFiat: nil,
            swapProvider: nil,
            feeCrypto: "",
            feeFiat: "",
            network: chain.name,
            explorerLink: explorerLink,
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: ChainStatusConfig.config(for: chain).estimatedTime,
            errorMessage: nil
        )
        do {
            try storage.save(data)
        } catch {
            logger.error("Save failed for txHash=\(txHash): \(error)")
        }
    }

    // MARK: - Record from KeysignPayload (co-signer path)

    func recordFromKeysignPayload(
        txHash: String,
        approveTxHash: String?,
        vault: Vault,
        keysignPayload: KeysignPayload
    ) {
        let isSwap = keysignPayload.swapPayload != nil

        if isSwap, let swapPayload = keysignPayload.swapPayload {
            recordSwap(
                txHash: txHash,
                approveTxHash: approveTxHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                fromCoin: swapPayload.fromCoin,
                toCoin: swapPayload.toCoin,
                fromAmountCrypto: keysignPayload.fromAmountString,
                fromAmountFiat: keysignPayload.fromAmountFiatString,
                toAmountCrypto: swapPayload.toAmountDecimal.formatForDisplay(),
                toAmountFiat: keysignPayload.toSwapAmountFiatString,
                fromAddress: keysignPayload.coin.address,
                toAddress: keysignPayload.toAddress,
                feeCrypto: "",
                feeFiat: "",
                chain: keysignPayload.coin.chain,
                explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: keysignPayload.coin.chain, txid: txHash),
                provider: swapPayload.providerName,
                // A co-signer never sees the initiator's `SwapTransaction`, so
                // the memo is the only thing telling it this swap row is a
                // resting limit order rather than a market swap. Without this,
                // the co-signing device runs the native poller against the row
                // and reports the order Successful on inbound confirmation —
                // the same lie, just on the other device.
                //
                // Only ERC20-source limit orders reach this branch (they ride a
                // `swapPayload` for the router's `depositWithExpiry`). Native
                // sources carry no swap payload and fall through to the send
                // branch below.
                swapTracking: isLimitSwapMemo(keysignPayload.memo)
                    ? THORChainLimitTrackingService.metadata(
                        broadcastHash: txHash,
                        sourceChain: keysignPayload.coin.chain
                    )
                    : nil
            )
        } else {
            recordSend(
                txHash: txHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                coin: keysignPayload.coin,
                amountCrypto: keysignPayload.toAmountWithTickerString,
                amountFiat: keysignPayload.toSendAmountFiatString,
                fromAddress: keysignPayload.coin.address,
                toAddress: keysignPayload.toAddress,
                feeCrypto: "",
                feeFiat: "",
                chain: keysignPayload.coin.chain,
                explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: keysignPayload.coin.chain, txid: txHash)
            )
        }

        if let approveTxHash, let approvePayload = keysignPayload.approvePayload {
            recordApprove(
                txHash: approveTxHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                coin: keysignPayload.coin,
                amountCrypto: approvePayload.amount.toDecimal(decimals: keysignPayload.coin.decimals).formatForDisplay(),
                spender: approvePayload.spender,
                chain: keysignPayload.coin.chain,
                explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: keysignPayload.coin.chain, txid: approveTxHash)
            )
        }
    }

    // MARK: - Update Status

    func updateStatus(txHash: String, pubKeyECDSA: String, status: TransactionHistoryStatus, errorMessage: String? = nil) {
        do {
            try storage.updateStatus(txHash: txHash, pubKeyECDSA: pubKeyECDSA, status: status, errorMessage: errorMessage)
        } catch {
            logger.error("Update status failed for txHash=\(txHash): \(error)")
        }
    }

    // MARK: - Swap tracking

    /// Attach swap-tracking metadata (route/swap ids + broadcast hash +
    /// source chain id + sub-provider) to an existing swap row, so the
    /// registered `SwapTrackingService` conformer for `providerKind` can
    /// drive polls from then on. Called by the done screen right after the
    /// broadcast, once the aggregator response is in hand.
    func attachSwapTracking(
        txHash: String,
        pubKeyECDSA: String,
        providerKind: String,
        swapId: String?,
        routeId: String?,
        broadcastHash: String,
        sourceChainId: String,
        subProvider: String?
    ) {
        do {
            try storage.attachSwapTracking(
                txHash: txHash,
                pubKeyECDSA: pubKeyECDSA,
                providerKind: providerKind,
                swapId: swapId,
                routeId: routeId,
                broadcastHash: broadcastHash,
                sourceChainId: sourceChainId,
                subProvider: subProvider
            )
        } catch {
            logger.error("Attach swap tracking failed for txHash=\(txHash): \(error)")
        }
    }
}
