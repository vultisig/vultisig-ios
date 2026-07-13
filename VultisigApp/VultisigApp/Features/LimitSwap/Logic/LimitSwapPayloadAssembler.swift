//
//  LimitSwapPayloadAssembler.swift
//  VultisigApp
//

import BigInt
import Foundation

enum LimitSwapAssemblyError: Error, Equatable {
    case sourceChainNotRoutable(Chain)
    case noInboundAddressForChain(String)
    /// The persisted `LimitOrderRecord.sourceAmount` (a BigInt-as-string) failed
    /// to parse back into a `BigInt`. Fail loud rather than sign a `0`-amount
    /// deposit — a silent `?? 0` would broadcast an empty transfer.
    case invalidSourceAmount(String)
    /// The `EnableAdvSwapQueue` mimir was not confirmed enabled at SIGN time.
    /// The entry screen gates placement, but the user may have lingered on the
    /// Verify screen while the queue was disabled — re-check live and fail closed
    /// so a `=<` order is never signed onto a network that would treat it as a
    /// market swap.
    case advancedSwapQueueDisabled
    /// THORChain has globally paused trading (`global_trading_paused`). A native
    /// RUNE `MsgDeposit` has no inbound vault, so it bypasses the per-chain
    /// inbound halt/pause filter the external-source branch applies — this is the
    /// fail-closed global-pause gate for the deposit path.
    case thorchainTradingPaused
}

/// Whether THORChain has globally paused trading, per a live `inbound_addresses`
/// list. THORChain sets `global_trading_paused` on EVERY inbound row when it
/// halts trading network-wide. A native RUNE `MsgDeposit` settles on THORChain
/// itself with no inbound vault, so it never passes through the per-chain halt
/// filter the external branch runs — this global signal is the gate applied
/// before signing a RUNE deposit. Pure so it is unit-testable without a fetch.
func isThorchainGloballyPaused(inbounds: [InboundAddress]) -> Bool {
    inbounds.contains { $0.global_trading_paused ?? false }
}

/// Whether a native RUNE `MsgDeposit` must be BLOCKED given the live inbound
/// list. Blocks when THORChain has globally paused trading, and — fail-closed —
/// when the list is empty: a real `inbound_addresses` response always carries
/// many chain rows, so an empty (but non-throwing) result means the pause state
/// is unverifiable and a deposit must not be signed against it. Pure so it is
/// unit-testable without a network fetch.
func shouldBlockRuneDeposit(inbounds: [InboundAddress]) -> Bool {
    inbounds.isEmpty || isThorchainGloballyPaused(inbounds: inbounds)
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

    // Sign-time fail-closed availability re-check. Placement was gated on the
    // `EnableAdvSwapQueue` mimir at the entry screen, but the mimir can flip
    // while the user sits on the Verify screen. Re-confirm live before building
    // anything signable — a `=<` order on a network with the queue disabled can
    // be treated as a market swap and execute at the wrong price. Mirrors the
    // market path's sign-time halt re-check.
    guard await ThorchainService.shared.isAdvancedSwapQueueEnabled() else {
        throw LimitSwapAssemblyError.advancedSwapQueueDisabled
    }

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
        // Native RUNE settles via `MsgDeposit` with no inbound vault, so it
        // NEVER passes through the per-chain inbound halt/pause filter the
        // external-source branch below applies (and `SwapHaltGate.isHalted`
        // finds no THOR inbound row, so the verify-screen gate reads it as
        // "not halted" too). THORChain's global trading pause still applies to
        // RUNE deposits — fetch live (cache-bypass, matching the external
        // branch) and fail CLOSED if it's set, so a resting order is never
        // signed while the network has globally paused trading. The throwing
        // fetch also fails closed on an unverifiable inbound fetch.
        let inbounds = try await ThorchainService.shared.fetchThorchainInboundAddressOrThrow(bypassCache: true)
        guard !shouldBlockRuneDeposit(inbounds: inbounds) else {
            throw LimitSwapAssemblyError.thorchainTradingPaused
        }
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
