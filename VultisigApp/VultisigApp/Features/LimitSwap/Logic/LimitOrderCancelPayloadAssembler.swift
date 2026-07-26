//
//  LimitOrderCancelPayloadAssembler.swift
//  VultisigApp
//
//  Resolves WHERE an L1-originated cancel is sent and WHAT it must carry: a
//  dust transfer to THORChain's inbound vault carrying the `m=<` memo, observed
//  by Bifrost and dispatched to the same modify handler a native `MsgDeposit`
//  reaches.
//
//  Only the resolution lives here. Building and signing the transaction itself
//  goes through the ordinary function-call send pipeline, which already handles
//  a memo-bearing native transfer on every supported chain — including EVM gas
//  estimation against the memo (`fetchSpecificForEVM` → `estimateGasLimit(tx:)`,
//  which passes `tx.memo` and takes `max(120000, estimate)`). A bespoke
//  assembler was written first and then removed: it would have needed its own
//  copy of the keysign ceremony navigation, and duplicating that to gain nothing
//  is how the fast-vault and paired-sign branches drift apart.
//
//  One known imprecision, deliberately left alone: `estimateGasLimit` estimates
//  against `.anyAddress` rather than the resolved inbound vault. For a plain
//  value transfer carrying a memo that is immaterial — base 21,000 plus ~40
//  bytes of calldata sits far under the 120,000 floor the estimate is maxed
//  against. It would only start to matter if an Asgard inbound address were
//  ever a contract rather than a plain account.
//
//  The `EnableAdvSwapQueue` mimir gate deliberately does NOT apply to a cancel.
//  Placement is gated and must be — a `=<` signed while the queue is disabled
//  can be treated as a market swap and execute at the wrong price. A cancel has
//  the opposite risk profile: if the mimir flips off while an order rests, the
//  order still exists and the user still needs a way out. Nothing here consults
//  it, and nothing should.
//

import BigInt
import Foundation

enum LimitOrderCancelAssemblyError: Error, Equatable, LocalizedError {
    case sourceChainNotRoutable(Chain)
    case noInboundAddressForChain(String)
    case dust(LimitOrderCancelDustError)

    var errorDescription: String? {
        switch self {
        case let .sourceChainNotRoutable(chain):
            return String(format: "limitSwap.cancel.error.chainNotRoutable".localized, chain.name)
        case .noInboundAddressForChain:
            return "limitSwap.cancel.error.noInboundAddress".localized
        case .dust:
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
///
/// ⚠️ `sourceCoin.decimals` is not optional context. `inbound.dust_threshold` is
/// quoted in THORChain's 1e8 fixed point on every chain; the coin's own
/// precision is what turns it into the smallest unit the signer needs.
@MainActor
func limitOrderCancelDust(for sourceCoin: Coin, inbound: InboundAddress) throws -> BigInt {
    do {
        return try limitOrderCancelDustAmount(
            walletCoreDustFloor: BigInt(sourceCoin.coinType.getFixedDustThreshold()),
            inboundDustThreshold: inbound.dust_threshold,
            decimals: sourceCoin.decimals,
            ceiling: sourceCoin.raw(for: limitOrderCancelDustCeiling(for: sourceCoin.chain)),
            chainSymbol: ThorchainService.getInboundChainName(for: sourceCoin.chain)
        )
    } catch let error as LimitOrderCancelDustError {
        throw LimitOrderCancelAssemblyError.dust(error)
    }
}
