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

    @MainActor
    static func send(
        txHash: String,
        chain: Chain,
        tx: SendTransaction?,
        vault: Vault
    ) -> DoneStatusService {
        DoneStatusService(poller: ChainPoller(
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
    @MainActor
    static func cosigner(
        keysignPayload: KeysignPayload,
        txHash: String,
        vault: Vault
    ) -> DoneStatusService {
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
