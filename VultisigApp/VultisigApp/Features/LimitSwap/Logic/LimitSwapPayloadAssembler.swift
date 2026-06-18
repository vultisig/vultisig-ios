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
/// Mirrors how the market-swap path assembles its keysign payload, with
/// two differences:
/// 1. `memo` is the limit-swap memo built client-side (`=<:...`) rather than
///    the API-provided market memo (`=>:...`).
/// 2. `swapPayload` is `nil` — the limit-ness lives entirely in the memo for
///    Phase 1; revisit if a chain helper turns out to require swap-payload
///    context for proper signing.
///
/// **Implementation detail:** `BlockChainService.fetchSwapBlockChainSpecific`
/// is the granular swap-shaped fetch on main (post-refactor PR #4332).
/// Passing `quote: nil` matches the limit-order shape (no market quote
/// exists) and `estimateSwapGasLimit` short-circuits to `nil` for that
/// case, so the downstream call never touches `fromAmount`.
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

    // Native RUNE / CACAO settle via `MsgDeposit` on the swap chain itself —
    // no Asgard inbound vault, no destination address. The Cosmos signer
    // ignores `toAddress` on `MsgDeposit` (chain-specific `isDeposit=true`
    // controls the message type), but the payload struct still requires
    // a value. Use the signer's own address as a placeholder, matching the
    // SDK convention in `getSwapDestinationAddress` for native sources.
    let toAddress: String
    if SwapCryptoLogic.isDeposit(fromCoin: sourceCoin) {
        toAddress = sourceCoin.address
    } else {
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
        if !sourceCoin.isNativeToken, let router = inbound.router, !router.isEmpty {
            toAddress = router
        } else {
            toAddress = inbound.address
        }
    }

    let chainSpecific = try await BlockChainService.shared.fetchSwapBlockChainSpecific(
        fromCoin: sourceCoin,
        toCoin: targetCoin,
        fromAmount: sourceCoin.decimal(for: sourceAmount),
        quote: nil
    )

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
///
/// THORChain and Maya native sources are intentionally excluded — those
/// settle via `MsgDeposit` on the swap chain itself (`SwapCryptoLogic.isDeposit`
/// flags them, the assembler branches before this lookup). If a future
/// caller forgets the deposit branch and reaches here for a native source,
/// the resulting `sourceChainNotRoutable` is a louder failure than building
/// a malformed payload with a bogus inbound address.
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
    default: return nil
    }
}
