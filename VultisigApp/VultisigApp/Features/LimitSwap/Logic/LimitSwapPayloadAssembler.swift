//
//  LimitSwapPayloadAssembler.swift
//  VultisigApp
//

import BigInt
import Foundation

enum LimitSwapAssemblyError: Error, Equatable, LocalizedError {
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
    /// An ERC20 source resolved a live inbound row with no router contract. A
    /// token deposit is the router's `depositWithExpiry` call, so without a
    /// router the tokens can't be deposited — fail loud rather than fall back to
    /// a plain transfer that would strand them on the vault with no memo.
    case noRouterForTokenSource(String)

    /// Friendly, localized message for the shared Verify screen's error alert
    /// (`SwapVerifyScreen` renders `error.localizedDescription`). Without this
    /// `LocalizedError` conformance the alert fell back to the raw NSError form
    /// — "(VultisigApp.LimitSwapAssemblyError error 3.)".
    var errorDescription: String? {
        switch self {
        case let .sourceChainNotRoutable(chain):
            return String(format: "limitSwap.assemblyError.sourceChainNotRoutable".localized, chain.name)
        case .noInboundAddressForChain:
            return "limitSwap.assemblyError.noInboundAddress".localized
        case .invalidSourceAmount:
            return "limitSwap.assemblyError.invalidSourceAmount".localized
        case .advancedSwapQueueDisabled:
            // Reuse the existing user-facing queue-disabled copy the entry form
            // already shows, so the same condition reads identically wherever it
            // surfaces.
            return "limitSwap.error.advancedSwapQueueDisabled".localized
        case .thorchainTradingPaused:
            return "limitSwap.assemblyError.thorchainTradingPaused".localized
        case .noRouterForTokenSource:
            return "limitSwap.assemblyError.noRouterForTokenSource".localized
        }
    }
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
/// Mirrors how the market-swap path assembles its keysign payload. The
/// limit-ness always lives in the `memo` (client-built `=<:...` vs the market
/// `=>:...`); how that memo reaches the chain depends on the source:
/// - **Native RUNE:** `MsgDeposit` on THORChain (no inbound vault).
/// - **Native gas asset (ETH/AVAX/BTC/…):** transfer to the Asgard inbound
///   vault with the memo in tx `data` / OP_RETURN — `swapPayload`/`approvePayload`
///   stay `nil`.
/// - **ERC20 source:** the router's `depositWithExpiry(vault, asset, amount,
///   memo, expiry)` call, which first needs `approve(router, amount)`. This
///   rides `swapPayload = .thorchain(...)` + `approvePayload`, mirroring the
///   market ERC20 THORChain swap exactly (approve + deposit signed in ONE
///   ceremony → `.regularWithApprove`); only the memo prefix differs. A token
///   source signed WITHOUT a swap payload would fall through to the plain
///   ERC20-transfer path in `KeysignViewModel`, dropping the memo and stranding
///   the tokens on the router — so it MUST ride the swap payload.
///
/// **Implementation detail:** `BlockChainService.fetchSwapBlockChainSpecific`
/// is the granular swap-shaped chain-specific fetch. Passing `quote: nil`
/// matches the limit-order shape (no market quote exists) so the downstream
/// call never touches `fromAmount`.
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
/// untouched. It is a no-op for non-EVM and token sources — a token
/// `depositWithExpiry` keeps the 600000 swap default, which safely over-covers
/// the router call.
///
/// `expectedToAmountDecimal` is the order's guaranteed-minimum output in the
/// target's natural units — surfaced only on the ERC20 swap payload for
/// cross-device "you receive" display (see `limitThorchainSwapPayload`); it
/// never influences signing. `now` is parameterised so the ERC20 deposit's
/// router expiry is deterministic under test.
@MainActor
func buildLimitSwapKeysignPayload(
    sourceCoin: Coin,
    targetCoin: Coin,
    sourceAmount: BigInt,
    memo: String,
    vault: Vault,
    expectedToAmountDecimal: Decimal = 0,
    now: Date = Date()
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
    // Non-nil only for an ERC20 source, which deposits via the router's
    // `depositWithExpiry` call (approve + deposit signed in one ceremony).
    var swapPayload: SwapPayload?
    var approvePayload: ERC20ApprovePayload?
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
        // Resolve the inbound chain symbol through the SHARED routing table
        // (`ThorchainService.getInboundChainName`, also used by the market halt
        // gate) rather than a duplicate switch, so limit and market can't drift.
        // A non-routable source — already excluded by the picker — fails loud
        // rather than resolving to a bogus symbol.
        guard isThorchainRoutable(chain: sourceCoin.chain) else {
            throw LimitSwapAssemblyError.sourceChainNotRoutable(sourceCoin.chain)
        }
        let chainSymbol = ThorchainService.getInboundChainName(for: sourceCoin.chain)

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

        if sourceCoin.isNativeToken {
            // Native gas asset (ETH / AVAX / BTC / …): deposit straight to the
            // Asgard inbound vault; the `=<` memo rides in the tx `data` (EVM)
            // / OP_RETURN (UTXO). No approval, no router call.
            toAddress = inbound.address
        } else {
            // ERC20 source: a THORChain token deposit is the router's
            // `depositWithExpiry(vault, asset, amount, memo, expiry)` call, which
            // first needs `approve(router, amount)`. Requires a router — without
            // one the tokens can't be deposited; fail loud rather than fall back
            // to a plain transfer that strands them.
            guard let router = inbound.router, !router.isEmpty else {
                throw LimitSwapAssemblyError.noRouterForTokenSource(chainSymbol)
            }
            toAddress = router
            approvePayload = ERC20ApprovePayload(amount: sourceAmount, spender: router)
            swapPayload = .thorchain(limitThorchainSwapPayload(
                sourceCoin: sourceCoin,
                targetCoin: targetCoin,
                sourceAmount: sourceAmount,
                vaultAddress: inbound.address,
                routerAddress: router,
                toAmountDecimal: expectedToAmountDecimal,
                now: now
            ))
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
        swapPayload: swapPayload,
        approvePayload: approvePayload,
        vault: vault
    )
}

/// Builds the `THORChainSwapPayload` that drives an ERC20 limit deposit's signed
/// `depositWithExpiry(vault, asset, amount, memo, expiry)` router call. Mirrors
/// the market ERC20 THORChain swap: `EVMHelper.getSwapPreSignedInputData` reads
/// `routerAddress` (tx `to`), `vaultAddress` (the Asgard vault, first ABI
/// param), `fromCoin.contractAddress` and `fromAmount` off this payload; the
/// `=<` limit memo rides on `KeysignPayload.memo`, NOT this payload.
///
/// `toAmountDecimal` is the order's guaranteed-MINIMUM output in the target's
/// natural units (the memo LIM expressed for display, via
/// `SwapTransaction.toAmountDecimal` → `limitOrderExpectedOutput`). It feeds
/// only cross-device SWAP display — the co-signer's "you receive" row — so a
/// resting limit order shows its LIM floor rather than 0. Signing and every
/// fund-safety gate ignore it (they read `transaction` / `toCoin.address`), so
/// its exact value can never affect what is signed. `toAmountLimit` stays "0":
/// it drives only the WalletCore native-RUNE `THORChainSwap.build` min-output
/// arg, which an ERC20 `depositWithExpiry` never reaches, and nothing displays
/// it.
///
/// `expirationTime` is the router's ON-CHAIN tx-execution deadline
/// (`require(block.timestamp < expiry)` inside `depositWithExpiry`) — a guard
/// that a stale, long-unconfirmed deposit tx can't execute — NOT the resting
/// order's lifetime (that is the memo's TTL, up to 3 days, checked per-block by
/// THORChain). The market path's 15-minute window is reused verbatim: once
/// THORChain observes the deposit (a block or two, far under 15m) the `=<` order
/// rests for its full memo TTL regardless of this value.
///
/// Pure so the router/vault/amount/expiry wiring is unit-testable without a
/// network fetch.
func limitThorchainSwapPayload(
    sourceCoin: Coin,
    targetCoin: Coin,
    sourceAmount: BigInt,
    vaultAddress: String,
    routerAddress: String,
    toAmountDecimal: Decimal,
    now: Date
) -> THORChainSwapPayload {
    THORChainSwapPayload(
        fromAddress: sourceCoin.address,
        fromCoin: sourceCoin,
        toCoin: targetCoin,
        vaultAddress: vaultAddress,
        routerAddress: routerAddress,
        fromAmount: sourceAmount,
        toAmountDecimal: toAmountDecimal,
        toAmountLimit: "0",
        streamingInterval: "0",
        streamingQuantity: "0",
        expirationTime: UInt64(now.addingTimeInterval(60 * 15).timeIntervalSince1970),
        isAffiliate: SwapCryptoLogic.isAffiliate
    )
}

/// Aligns a native-EVM limit deposit's gas limit with the market native-EVM
/// THORChain deposit (`estimateSwapGasLimit(.thorchain)` = 120000). See the long
/// comment on `buildLimitSwapKeysignPayload` for the full rationale + the
/// signing-path maintainer-review flag.
///
/// Pure so the gas-limit decision is unit-testable without a network fetch.
/// Changes ONLY the EVM gas-limit field (via `overridingEVMGasLimit`); a no-op
/// for non-EVM chains and for non-native (token) EVM sources. A token source's
/// `depositWithExpiry` router call is more expensive than a native transfer, so
/// it intentionally keeps the 600000 swap default rather than the 120000
/// native-transfer figure.
func limitDepositChainSpecific(_ specific: BlockChainSpecific, sourceCoin: Coin) -> BlockChainSpecific {
    guard sourceCoin.chainType == .EVM, sourceCoin.isNativeToken else {
        return specific
    }
    return specific.overridingEVMGasLimit(BigInt(EVMHelper.defaultERC20TransferGasUnit))
}
