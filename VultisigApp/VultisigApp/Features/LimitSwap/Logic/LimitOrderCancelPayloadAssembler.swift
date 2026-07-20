//
//  LimitOrderCancelPayloadAssembler.swift
//  VultisigApp
//
//  Builds the signable payload for cancelling a limit order FROM the L1 chain
//  that funded it — a dust transfer to THORChain's inbound vault carrying the
//  `m=<` memo, observed by Bifrost and dispatched to the same modify handler a
//  native `MsgDeposit` reaches.
//
//  Separate from `buildLimitSwapKeysignPayload` (which PLACES an order) rather
//  than parameterised into it, because almost none of that function survives
//  contact with a cancel: no ERC20/router branch, no LIM, no advanced-swap-queue
//  gate, and a send-shaped rather than swap-shaped chain-specific fetch. What
//  the two genuinely share is inbound-vault resolution, which is extracted
//  below so the halt/pause filter cannot drift between them.
//

import BigInt
import Foundation

enum LimitOrderCancelAssemblyError: Error, Equatable, LocalizedError {
    case sourceChainNotRoutable(Chain)
    case noInboundAddressForChain(String)
    /// The memo does not fit the source chain's per-transaction budget, and
    /// unlike a placement memo there is nothing in it that may be shortened.
    /// Overwhelmingly this is an ERC20 target from a UTXO source.
    case memoTooLongForSourceChain(actual: Int, limit: Int)
    case dust(LimitOrderCancelDustError)
    /// The coin handed in was not the chain's native gas asset.
    ///
    /// Enforced rather than merely documented because the failure is silent and
    /// expensive: a token coin here would build a plain ERC20 transfer to the
    /// Asgard vault carrying an `m=<` memo. THORChain does not credit tokens
    /// arriving outside a router `depositWithExpiry`, so the tokens would be
    /// stranded on the vault and the order would remain resting.
    case sourceCoinNotNative(Chain)

    var errorDescription: String? {
        switch self {
        case let .sourceChainNotRoutable(chain):
            return String(format: "limitSwap.cancel.error.chainNotRoutable".localized, chain.name)
        case .noInboundAddressForChain:
            return "limitSwap.cancel.error.noInboundAddress".localized
        case .memoTooLongForSourceChain:
            return "limitSwap.cancel.error.memoTooLong".localized
        case .dust:
            return "limitSwap.cancel.error.dustUnavailable".localized
        case .sourceCoinNotNative:
            return "limitSwap.cancel.error.dustUnavailable".localized
        }
    }
}

/// Resolve the live, non-halted THORChain inbound vault for `chain`.
///
/// Cache-bypassing on purpose: the address selected here is signed against, and
/// a stale cached inbound can lag a vault rotation by up to the 5-minute TTL —
/// signing to a rotated-out vault sends funds nowhere recoverable. Missing pause
/// flags read as "not paused", matching `SwapHaltGate.isHalted(chain:in:)`.
///
/// Fails closed: a fetch error yields an empty list and the `first(where:)`
/// below throws rather than falling back to anything.
@MainActor
func resolveThorchainInboundVault(for chain: Chain) async throws -> InboundAddress {
    guard isThorchainRoutable(chain: chain) else {
        throw LimitOrderCancelAssemblyError.sourceChainNotRoutable(chain)
    }
    let chainSymbol = ThorchainService.getInboundChainName(for: chain)
    let inbounds = await ThorchainService.shared.fetchThorchainInboundAddress(bypassCache: true)
    guard let inbound = inbounds.first(where: { entry in
        entry.chain.uppercased() == chainSymbol.uppercased()
        && !entry.halted
        && !(entry.global_trading_paused ?? false)
        && !(entry.chain_trading_paused ?? false)
    }) else {
        throw LimitOrderCancelAssemblyError.noInboundAddressForChain(chainSymbol)
    }
    return inbound
}

/// The dust a cancel on this chain must attach, in the coin's smallest units.
///
/// Split out from the assembler so the confirmation screen can show the user the
/// exact amount they are about to donate BEFORE they sign — everything attached
/// to an `m=<` is `donateToPool`'d with no refund path, so a generic "network
/// fees apply" would be actively misleading. On DOGE this is 2 whole DOGE.
@MainActor
func limitOrderCancelDust(for sourceCoin: Coin, inbound: InboundAddress) throws -> BigInt {
    do {
        return try limitOrderCancelDustAmount(
            walletCoreDustFloor: BigInt(sourceCoin.coinType.getFixedDustThreshold()),
            inboundDustThreshold: inbound.dust_threshold,
            ceiling: sourceCoin.raw(for: limitOrderCancelDustCeiling(for: sourceCoin.chain)),
            chainSymbol: ThorchainService.getInboundChainName(for: sourceCoin.chain)
        )
    } catch let error as LimitOrderCancelDustError {
        throw LimitOrderCancelAssemblyError.dust(error)
    }
}

/// Build the signable payload for an L1-originated cancel.
///
/// - Parameter sourceCoin: the vault's NATIVE gas coin on the order's source
///   chain — never the order's own asset. A cancel moves no tokens, so even an
///   ERC20-funded order is cancelled with a native dust transfer: no router, no
///   approve, no `depositWithExpiry`.
///
/// ⚠️ **Deliberately NOT gated on the `EnableAdvSwapQueue` mimir.** Placement is
/// gated, and must be — a `=<` order signed while the queue is disabled can be
/// treated as a market swap and execute at the wrong price. A CANCEL has the
/// opposite risk profile: if the mimir flips off while an order is resting, the
/// order still exists and the user still needs a way out. Gating this would
/// strand them with funds committed and no exit.
@MainActor
func buildLimitOrderCancelKeysignPayload(
    sourceCoin: Coin,
    memo: String,
    vault: Vault
) async throws -> KeysignPayload {
    // Enforced first, and before any network call. A token coin here would
    // build a plain transfer to the Asgard vault, which THORChain does not
    // credit outside a router deposit — the tokens would simply be stranded.
    // The doc comment above is not sufficient protection for that.
    guard sourceCoin.isNativeToken else {
        throw LimitOrderCancelAssemblyError.sourceCoinNotNative(sourceCoin.chain)
    }

    // Checked before any network call: this is a property of the memo and the
    // chain, so failing here costs nothing and gives an honest reason.
    let byteLimit = limitMemoByteLimit(for: sourceCoin.chain.chainType)
    guard limitOrderCancelMemoFits(memo, sourceChainKind: sourceCoin.chain.chainType) else {
        throw LimitOrderCancelAssemblyError.memoTooLongForSourceChain(
            actual: memo.utf8.count,
            limit: byteLimit
        )
    }

    let inbound = try await resolveThorchainInboundVault(for: sourceCoin.chain)
    let dust = try limitOrderCancelDust(for: sourceCoin, inbound: inbound)

    // Send-shaped, not swap-shaped. `fetchSwapBlockChainSpecific` exists to size
    // a deposit that moves real value through a router; this is a plain
    // memo-bearing transfer, and the send path additionally runs
    // `resolveEVMSendGasLimit`, which sizes gas against the real recipient and
    // the memo. A long memo under a flat gas default reverts on-chain with the
    // keysign already spent.
    let chainSpecific = try await BlockChainService.shared.fetchSendBlockChainSpecific(
        coin: sourceCoin,
        toAddress: inbound.address,
        amount: dust,
        memo: memo,
        sendMaxAmount: false,
        isDeposit: false,
        transactionType: .unspecified,
        gasLimit: nil,
        customGasLimit: nil,
        feeMode: .default,
        fromAddress: sourceCoin.address
    )

    return try await KeysignPayloadFactory().buildTransfer(
        coin: sourceCoin,
        toAddress: inbound.address,
        amount: dust,
        memo: memo,
        chainSpecific: chainSpecific,
        vault: vault
    )
}
