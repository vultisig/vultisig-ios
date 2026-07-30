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
    private let logger = Log.wallet.other

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
    ///
    /// The row's `type` is DERIVED from `swapTracking` (see `rowType(for:)`) —
    /// a limit-tracked row is a `.limit` row, always.
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
            type: Self.rowType(for: swapTracking),
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

    // MARK: - Row type

    /// The row type a swap-shaped record carries.
    ///
    /// Derived from the tracking provider rather than passed in, because the
    /// two must never disagree: the Limit Orders tab filters on `type`, while
    /// the polling-arbitration gate turns on `swapTracking`. A limit order
    /// typed `.swap` would poll correctly but be missing from the tab the
    /// done-screen banner sends the user to; a `.swap` typed `.limit` would
    /// show up in a tab it has no business in. Deriving one from the other
    /// makes the mismatch unrepresentable.
    private static func rowType(for swapTracking: SwapTrackingMetadataData?) -> TransactionHistoryType {
        swapTracking?.providerKind == THORChainLimitTrackingService.providerKind ? .limit : .swap
    }

    // MARK: - Record a native-source limit order (co-signer path)

    /// Records a limit order placed from a NATIVE source asset (RUNE, BTC, …).
    ///
    /// These carry no `swapPayload` — they are a plain deposit whose `=<` memo
    /// is the entire order — so the co-signing device cannot see the target
    /// coin or amount at all. It used to fall through to `recordSend`, which
    /// produced a `send` row with NO tracking metadata: the order was both
    /// missing from the Limit Orders tab and reported Successful by the native
    /// poller as soon as the deposit confirmed.
    ///
    /// The to-side is deliberately left `nil` rather than guessed. The memo
    /// does carry the target asset and the LIM, but resolving those to a real
    /// `Coin` (for a logo and decimals) is exactly the kind of reconstruction
    /// that produces a confidently wrong number on an order card. A row that
    /// admits it only knows the source side is honest; the initiating device
    /// records the full picture, and both devices agree on status.
    func recordLimitOrder(
        txHash: String,
        pubKeyECDSA: String,
        coin: Coin,
        amountCrypto: String,
        amountFiat: String,
        fromAddress: String,
        toAddress: String,
        chain: Chain,
        explorerLink: String
    ) {
        let data = TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: pubKeyECDSA,
            type: .limit,
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
            // A placed `=<` order always routes through THORChain — the same
            // fixed provider the initiator records.
            swapProvider: "THORChain",
            feeCrypto: "",
            feeFiat: "",
            network: chain.name,
            explorerLink: explorerLink,
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: ChainStatusConfig.config(for: chain).estimatedTime,
            errorMessage: nil,
            swapTracking: THORChainLimitTrackingService.metadata(
                broadcastHash: txHash,
                sourceChain: chain
            )
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

    // MARK: - Record an XRPL trust-line activation

    /// Records an XRPL `TrustSet` — the transaction that opens a trust line.
    ///
    /// Modelled on `recordApprove`, because the two are the same kind of
    /// transaction: permissioning, not transfer. The difference from an approve
    /// is that this row carries NO amount at all. A TrustSet's signed amount is
    /// the line's LIMIT, so any value in `amountCrypto` would be read as a
    /// quantity that moved — which is the entire bug this exists to close.
    ///
    /// The fee IS recorded, unlike an approve (whose call site has none to
    /// hand). A trust line costs a fee and locks an owner reserve, and that cost
    /// is the main thing history still owes the user for a transaction that
    /// moved nothing.
    ///
    /// - Parameters:
    ///   - ticker: the trusted currency as a human reads it — resolved from the
    ///     on-ledger currency code, so a 40-character hex currency shows as
    ///     `RLUSD` rather than its hex.
    ///   - issuer: the account the line is with. Stored in `toAddress` because
    ///     the row schema has nowhere else, and relabelled by the detail sheet:
    ///     a TrustSet has no XRPL destination, so the issuer must never be
    ///     presented as a recipient.
    func recordTrustLineActivation(
        txHash: String,
        pubKeyECDSA: String,
        coin: Coin,
        ticker: String,
        issuer: String,
        feeCrypto: String,
        feeFiat: String,
        explorerLink: String
    ) {
        let data = Self.trustLineActivationRow(
            txHash: txHash,
            pubKeyECDSA: pubKeyECDSA,
            coin: coin,
            ticker: ticker,
            issuer: issuer,
            feeCrypto: feeCrypto,
            feeFiat: feeFiat,
            explorerLink: explorerLink
        )
        do {
            try storage.save(data)
        } catch {
            logger.error("Save failed for txHash=\(txHash): \(error)")
        }
    }

    /// The row a trust-line activation persists.
    ///
    /// Pure and `static` so the row's CONTENT can be pinned by tests — the
    /// recorder is a `private init()` singleton writing to SwiftData, so the
    /// wired path isn't reachable from a unit test. The routing that reaches it
    /// is pinned separately by `TransactionHistoryRecording.isTrustLineActivation`.
    static func trustLineActivationRow(
        txHash: String,
        pubKeyECDSA: String,
        coin: Coin,
        ticker: String,
        issuer: String,
        feeCrypto: String,
        feeFiat: String,
        explorerLink: String
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: txHash,
            approveTxHash: nil,
            pubKeyECDSA: pubKeyECDSA,
            type: .trustLineActivation,
            status: .inProgress,
            // Taken from the coin rather than pinned to `.ripple`, even though a
            // TrustSet is XRPL-only: the explorer link and the native poller
            // both resolve their chain from this field, and a value that could
            // disagree with the coin the row shows is a link pointing at the
            // wrong ledger.
            chainRawValue: coin.chain.rawValue,
            coinTicker: ticker,
            coinLogo: coin.logo,
            coinChainLogo: coin.tokenChainLogo,
            // ⚠️ Deliberately empty, both of them. The only number a TrustSet
            // carries is the trust-line limit, and the whole point of this row
            // type is that the limit is not a quantity that moved. The card and
            // the detail sheet branch away from their amount slots for this
            // type, so nothing formats these.
            amountCrypto: .empty,
            amountFiat: .empty,
            fromAddress: coin.address,
            toAddress: issuer,
            toCoinTicker: nil,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: nil,
            toAmountFiat: nil,
            swapProvider: nil,
            feeCrypto: feeCrypto,
            feeFiat: feeFiat,
            network: coin.chain.name,
            explorerLink: explorerLink,
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: ChainStatusConfig.config(for: coin.chain).estimatedTime,
            errorMessage: nil
        )
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
                // sources carry no swap payload and take the limit-order
                // branch below.
                swapTracking: isLimitSwapMemo(keysignPayload.memo)
                    ? THORChainLimitTrackingService.metadata(
                        broadcastHash: txHash,
                        sourceChain: keysignPayload.coin.chain
                    )
                    : nil
            )
        } else if isLimitSwapMemo(keysignPayload.memo) {
            // Native-source limit order: no swap payload, so the `=<` memo is
            // the only evidence this deposit is an order at all. Recorded as a
            // `.limit` row rather than a `send` row — it belongs in the Limit
            // Orders tab, and it needs the tracking metadata that stands the
            // deposit-confirming native poller down.
            recordLimitOrder(
                txHash: txHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                coin: keysignPayload.coin,
                amountCrypto: keysignPayload.toAmountWithTickerString,
                amountFiat: keysignPayload.toSendAmountFiatString,
                fromAddress: keysignPayload.coin.address,
                toAddress: keysignPayload.toAddress,
                chain: keysignPayload.coin.chain,
                explorerLink: ExplorerLinkBuilder.getExplorerURL(chain: keysignPayload.coin.chain, txid: txHash)
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
