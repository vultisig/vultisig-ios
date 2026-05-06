//
//  LimitSwapPayloadAssembler.swift
//  VultisigApp
//

import BigInt
import Foundation

enum LimitSwapAssemblyError: Error, Equatable {
    case sourceChainNotRoutable(Chain)
    case noInboundAddressForChain(String)
}

/// Assembles the `KeysignPayload` for a placed limit swap.
///
/// Composes the existing `ThorchainService` (inbound vault lookup),
/// `BlockChainService` (chain-specific fee/nonce/etc. fetch), and
/// `KeysignPayloadFactory` (UTXO selection + final payload construction).
///
/// Mirrors how `SwapCryptoLogic.buildSwapKeysignPayload(tx:vault:)` does the
/// same for market swaps with two differences:
/// 1. `memo` is the limit-swap memo built client-side (`=<:...`) rather than
///    the API-provided market memo (`=>:...`).
/// 2. `swapPayload` is `nil` — the limit-ness lives entirely in the memo for
///    Phase 1; revisit if a chain helper turns out to require swap-payload
///    context for proper signing.
///
/// **Implementation detail:** `BlockChainService` exposes only a transaction-
/// shaped overload (`fetchSpecific(tx: SwapTransaction)`); the granular
/// `fetchSpecific(for:action:...)` lives in a `private extension`. So we
/// populate a transient `SwapTransaction` with the limit data and use the
/// public overload — `estimateSwapGasLimit` handles `tx.quote == nil`
/// gracefully (returns `nil` for non-EVM and EVM-without-quote).
///
/// **Phase 1 scope:** native source coins only. ERC20 sources require an
/// approval-keysign-first flow that's deferred to Phase 2.
@MainActor
func buildLimitSwapKeysignPayload(
    sourceCoin: Coin,
    targetCoin: Coin,
    sourceAmount: BigInt,
    memo: String,
    vault: Vault
) async throws -> KeysignPayload {

    guard let chainSymbol = thorchainInboundChainSymbol(for: sourceCoin.chain) else {
        throw LimitSwapAssemblyError.sourceChainNotRoutable(sourceCoin.chain)
    }

    // Fetch THORChain inbound vault address. Filter halted / paused chains.
    let inbounds = await ThorchainService.shared.fetchThorchainInboundAddress()
    guard let inbound = inbounds.first(where: { entry in
        entry.chain.uppercased() == chainSymbol.uppercased()
        && !entry.halted
        && !entry.global_trading_paused
        && !entry.chain_trading_paused
    }) else {
        throw LimitSwapAssemblyError.noInboundAddressForChain(chainSymbol)
    }

    // ERC20 source → router contract; native source → inbound vault.
    let toAddress: String
    if !sourceCoin.isNativeToken, let router = inbound.router, !router.isEmpty {
        toAddress = router
    } else {
        toAddress = inbound.address
    }

    // Build a transient SwapTransaction so we can use the public
    // BlockChainService.fetchSpecific(tx:) overload. Quote is nil — no market
    // quote exists for limit orders. The downstream gasLimit estimator
    // handles nil-quote gracefully.
    let transientTx = SwapTransaction()
    transientTx.fromCoin = sourceCoin
    transientTx.toCoin = targetCoin
    transientTx.quote = nil

    let chainSpecific = try await BlockChainService.shared.fetchSpecific(tx: transientTx)

    let factory = KeysignPayloadFactory()
    return try await factory.buildTransfer(
        coin: sourceCoin,
        toAddress: toAddress,
        amount: sourceAmount,
        memo: memo,
        chainSpecific: chainSpecific,
        swapPayload: nil,
        approvePayload: nil,
        vault: vault
    )
}

/// Maps an iOS `Chain` to the THORChain inbound-address `chain` field.
/// Returns `nil` for chains not currently routable through THORChain.
private func thorchainInboundChainSymbol(for chain: Chain) -> String? {
    switch chain {
    case .bitcoin: return "BTC"
    case .ethereum: return "ETH"
    case .litecoin: return "LTC"
    case .dogecoin: return "DOGE"
    case .bitcoinCash: return "BCH"
    case .avalanche: return "AVAX"
    case .bscChain: return "BSC"
    case .gaiaChain: return "GAIA"
    case .thorChain, .thorChainChainnet, .thorChainStagenet:
        return "THOR"
    default: return nil
    }
}
