//
//  DoneStatusServiceFactory.swift
//  VultisigApp
//
//  Single dispatch site that picks the right `DoneStatusPoller` for
//  each done-screen entry point. One factory method per flow:
//
//    - `send(...)`         — Send initiator + cosigner Send (RPC poll)
//    - `swap(...)`         — Swap initiator (SwapKit `/track` or RPC)
//    - `qbtcClaim(...)`    — QBTC claim (RPC poll on .qbtc)
//    - `cosigner(...)`     — Cosigner Send / Swap (dispatches on
//                            `KeysignPayload.swapPayload`)
//    - `signedMessage()`   — Custom-message signing (no poll)
//
//  Consumers never construct pollers directly; new backends land by
//  adding a poller conformer + a factory entry. The factory is the only
//  layer that needs to know about route discriminants (SwapKit vs
//  THORChain/Maya/1inch/etc.).
//

import Foundation

enum DoneStatusServiceFactory {

    /// - Note: a limit-order CANCEL is matched first. It needs a poller that can
    ///   see the transaction's own `code` — a `MsgDeposit` the handler refuses
    ///   produces no Midgard action, so `ChainPoller` would report nothing at
    ///   all for the one failure this feature has to surface — and it is the
    ///   only place the cancel is credited to the order it names.
    @MainActor
    static func send(
        txHash: String,
        chain: Chain,
        tx: SendTransaction?,
        vault: Vault
    ) -> DoneStatusService {
        if let cancelContext = tx?.limitCancelContext {
            return DoneStatusService(poller: LimitOrderCancelPoller(
                txHash: txHash,
                chain: chain,
                request: cancelContext,
                pubKeyECDSA: vault.pubKeyECDSA
            ))
        }
        return DoneStatusService(poller: ChainPoller(
            txHash: txHash,
            chain: chain,
            coinTicker: tx?.coin.ticker,
            amount: tx.map { "\($0.amount) \($0.coin.ticker)" },
            toAddress: tx?.toAddress,
            pubKeyECDSA: vault.pubKeyECDSA
        ))
    }

    @MainActor
    static func swap(
        txHash: String,
        transaction: SwapTransaction,
        vault: Vault
    ) -> DoneStatusService {
        // Checked before the SwapKit branch only for symmetry with the
        // cosigner dispatch below; a limit order carries no quote at all, so
        // the two conditions are mutually exclusive by construction.
        if transaction.isLimit {
            return DoneStatusService(poller: LimitOrderPoller(
                txHash: txHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                sourceChain: transaction.fromCoin.chain
            ))
        }
        if case .swapkit = transaction.quote {
            return DoneStatusService(poller: SwapKitPoller.initiator(
                transaction: transaction,
                txHash: txHash,
                pubKeyECDSA: vault.pubKeyECDSA
            ))
        }
        return DoneStatusService(poller: ChainPoller(
            txHash: txHash,
            chain: transaction.fromCoin.chain,
            coinTicker: transaction.fromCoin.ticker,
            amount: "\(transaction.fromAmount) \(transaction.fromCoin.ticker)",
            toAddress: transaction.toCoin.address,
            pubKeyECDSA: vault.pubKeyECDSA
        ))
    }

    @MainActor
    static func qbtcClaim(
        result: QBTCClaimRunResult,
        qbtcCoin: Coin,
        vault: Vault
    ) -> DoneStatusService {
        DoneStatusService(poller: ChainPoller(
            txHash: result.txHashHex,
            chain: .qbtc,
            coinTicker: qbtcCoin.ticker,
            amount: QBTCClaimAmountFormatter.formatQbtc(sats: result.totalSatsClaimed),
            toAddress: qbtcCoin.address,
            pubKeyECDSA: vault.pubKeyECDSA
        ))
    }

    /// Cosigner dispatch. Routes SwapKit swaps to `SwapKitPoller.cosigner`
    /// — the SwapKit fields ride on
    /// `KeysignPayload.swapPayload(.swapkit(SwapKitSwapPayload))`, so the
    /// peer device can attach the `/track` poll the same way the
    /// initiator does. Everything else (Send, THORChain/Maya swap,
    /// 1inch/Kyber/LiFi swap) falls through to the source-chain RPC
    /// poller — same path the initiator uses outside SwapKit routes.
    ///
    /// Limit orders are matched FIRST, and on the memo rather than the
    /// payload: a co-signer never sees the initiator's `SwapTransaction`, so
    /// the `=<` prefix is the only thing identifying a resting order. It has
    /// to precede the SwapKit branch because an ERC20-source limit order DOES
    /// carry a swap payload (for the router's `depositWithExpiry`) — though
    /// never a `.swapkit` one, so the order is belt-and-braces. Native-source
    /// orders carry no payload at all and would otherwise fall to the RPC
    /// poller and report the same premature success as the initiator did.
    /// This mirrors the identical gate in
    /// `TransactionHistoryRecorder.recordFromKeysignPayload`.
    @MainActor
    static func cosigner(
        keysignPayload: KeysignPayload,
        txHash: String,
        vault: Vault
    ) -> DoneStatusService {
        if isLimitSwapMemo(keysignPayload.memo) {
            return DoneStatusService(poller: LimitOrderPoller(
                txHash: txHash,
                pubKeyECDSA: vault.pubKeyECDSA,
                sourceChain: keysignPayload.coin.chain
            ))
        }
        if case .swapkit(let swapKitPayload) = keysignPayload.swapPayload {
            return DoneStatusService(poller: SwapKitPoller.cosigner(
                payload: swapKitPayload,
                sourceChain: keysignPayload.coin.chain,
                txHash: txHash,
                pubKeyECDSA: vault.pubKeyECDSA
            ))
        }
        return DoneStatusService(poller: ChainPoller(
            txHash: txHash,
            chain: keysignPayload.coin.chain,
            coinTicker: keysignPayload.coin.ticker,
            amount: keysignPayload.toAmountWithTickerString,
            toAddress: keysignPayload.toAddress,
            pubKeyECDSA: vault.pubKeyECDSA
        ))
    }

    @MainActor
    static func signedMessage() -> DoneStatusService {
        DoneStatusService(poller: NoPoller(initialStatus: .confirmed))
    }
}
