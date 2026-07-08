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
/// exists) so the downstream call never touches `fromAmount`.
///
/// **Native-EVM gas limit (signing-path, maintainer-review):** with `quote:
/// nil`, `estimateSwapGasLimit` returns `nil` and `fetchSwapBlockChainSpecific`
/// falls back to `normalizeGasLimit(.swap)` = `defaultETHSwapGasUnit` (600000).
/// The MARKET native-EVM THORChain deposit — the byte-identical operation, only
/// the memo prefix differs (`=>` vs `=<`) — instead uses
/// `defaultERC20TransferGasUnit` (120000) via `estimateSwapGasLimit(.thorchain)`.
/// We align the limit deposit to that same 120000 (`limitDepositChainSpecific`)
/// so the two paths gas the identical deposit identically and the limit path
/// doesn't over-reserve 5× the fee headroom. This changes ONLY the EVM gas-limit
/// field (via `overridingEVMGasLimit`); maxFeePerGas / priority / nonce are
/// untouched. It is a no-op for non-EVM and token sources.
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

    // Native RUNE settles via `MsgDeposit` on THORChain itself — no Asgard
    // inbound vault, no destination address. The Cosmos signer ignores
    // `toAddress` on `MsgDeposit` (chain-specific `isDeposit=true` controls the
    // message type), but the payload struct still requires a value. Use the
    // signer's own address as a placeholder, matching the SDK convention in
    // `getSwapDestinationAddress` for native sources.
    //
    // The deposit branch is gated on THORChain-native specifically, NOT the
    // shared `SwapCryptoLogic.isDeposit` (which also returns true for Maya /
    // CACAO). Maya isn't THORChain-routable — the picker already excludes it
    // via `isThorchainRoutable` — so a Maya coin reaching here is a bug; let it
    // fall through to `thorchainInboundChainSymbol` and fail loud as
    // `sourceChainNotRoutable` rather than build a cross-protocol MsgDeposit.
    let toAddress: String
    if SwapCryptoLogic.isDeposit(fromCoin: sourceCoin),
       thorchainChainPrefix(for: sourceCoin.chain) == "THOR" {
        toAddress = sourceCoin.address
    } else {
        guard let chainSymbol = thorchainInboundChainSymbol(for: sourceCoin.chain) else {
            throw LimitSwapAssemblyError.sourceChainNotRoutable(sourceCoin.chain)
        }

        // Live, cache-bypassing inbound fetch. The sign-time halt gate re-checks
        // halt status against a fresh fetch; the destination address selected
        // here must come from that same live view, or we could sign to a
        // vault/router the gate never validated (a stale cached inbound can lag
        // a vault rotation by up to the 5-minute TTL). Fail closed: on a fetch
        // error the list is empty and the `first(where:)` below throws.
        let inbounds = await ThorchainService.shared.fetchThorchainInboundAddress(bypassCache: true)
        guard let inbound = inbounds.first(where: { entry in
            // Missing pause flags read as "not paused" — same convention as
            // `SwapHaltGate.isHalted(chain:in:)` on the market path.
            entry.chain.uppercased() == chainSymbol.uppercased()
            && !entry.halted
            && !(entry.global_trading_paused ?? false)
            && !(entry.chain_trading_paused ?? false)
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

    let fetchedSpecific = try await BlockChainService.shared.fetchSwapBlockChainSpecific(
        fromCoin: sourceCoin,
        toCoin: targetCoin,
        fromAmount: sourceCoin.decimal(for: sourceAmount),
        quote: nil
    )
    let chainSpecific = limitDepositChainSpecific(fetchedSpecific, sourceCoin: sourceCoin)

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

/// Aligns a native-EVM limit deposit's gas limit with the market native-EVM
/// THORChain deposit (`estimateSwapGasLimit(.thorchain)` = 120000). See the long
/// comment on `buildLimitSwapKeysignPayload` for the full rationale + the
/// signing-path maintainer-review flag.
///
/// Pure so the gas-limit decision is unit-testable without a network fetch.
/// Changes ONLY the EVM gas-limit field (via `overridingEVMGasLimit`); a no-op
/// for non-EVM chains and for non-native (token) EVM sources — token sources are
/// Phase 2 and never reach here.
func limitDepositChainSpecific(_ specific: BlockChainSpecific, sourceCoin: Coin) -> BlockChainSpecific {
    guard sourceCoin.chainType == .EVM, sourceCoin.isNativeToken else {
        return specific
    }
    return specific.overridingEVMGasLimit(BigInt(EVMHelper.defaultERC20TransferGasUnit))
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
