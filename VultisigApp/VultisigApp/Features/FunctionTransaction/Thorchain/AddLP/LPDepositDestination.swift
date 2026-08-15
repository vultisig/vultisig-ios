//
//  LPDepositDestination.swift
//  VultisigApp
//
//  Where a liquidity deposit is sent, resolved for the asset being deposited.
//
//  The asset travels inside the answer, and that is the whole point of the
//  type. A pool picker can reassign which asset a deposit moves at any moment,
//  and a destination resolved for the previous one is a wrong-destination
//  signature: an ERC-20 router used as the recipient of a native transfer, or
//  an inbound vault approved as an ERC-20 spender. A destination that cannot
//  say which asset it belongs to cannot be checked against the asset in hand,
//  so it is stored with one.
//

import Foundation

/// Which of a liquidity position's two assets a deposit moves.
///
/// THORChain and MayaChain positions always carry the protocol's own asset —
/// RUNE, CACAO — in `coin1` and the L1 asset in `coin2`, so `.coin1` is the
/// protocol-side deposit and `.coin2` is the L1 side.
enum LPDepositSide: Hashable {
    case coin1
    case coin2
}

/// What the app currently knows about where a liquidity deposit goes.
///
/// Only `.protocolNative` and `.inbound` can produce a transaction; every other
/// state is something the user is told rather than something they sign through.
enum LPDepositDestination: Equatable {
    /// Not resolved yet.
    ///
    /// Deliberately distinct from every failure below: nothing is wrong, the
    /// answer simply has not arrived, and a form in this state is fully usable.
    /// Conflating "not yet known" with "no destination" is what let a stale
    /// value pass a `!isEmpty` check.
    case unresolved
    /// The deposit is a `MsgDeposit` on the protocol's own chain. There is no
    /// L1 inbound to send to and the empty recipient is the correct one — which
    /// is why this is a resolved state and not an absent one.
    case protocolNative(asset: CoinMeta)
    /// The L1 inbound vault (native assets) or the router contract (ERC-20).
    case inbound(asset: CoinMeta, address: String, requiresApproval: Bool)
    /// THORChain has paused liquidity-provider actions for the source chain.
    case lpActionsPaused(chain: String)
    /// THORChain lists no inbound vault for the source chain at all.
    case inboundNotFound(chain: String)
    /// An ERC-20 deposit whose chain reports no router to approve.
    case routerNotAvailable(chain: String)
    /// The protocol this pool belongs to has no L1 deposit path wired here.
    case unsupportedProtocol
}

extension LPDepositDestination {
    /// The recipient for a deposit of `coin`, or nil when this answer cannot be
    /// used for it.
    ///
    /// Returns nil whenever the answer was resolved for a **different** asset.
    /// That is the guard, not a nicety: the caller has no other way to tell a
    /// destination resolved a moment ago for the asset in hand from one
    /// resolved for the asset the pool picker just replaced.
    ///
    /// An empty string is a real answer here — a protocol-native deposit rides
    /// a `MsgDeposit` and names no recipient — so callers must distinguish
    /// `nil` from `""` and never test emptiness to decide validity.
    func depositAddress(for coin: Coin) -> String? {
        switch self {
        case .protocolNative(let asset):
            return asset == coin.toCoinMeta() ? .empty : nil
        case .inbound(let asset, let address, _):
            return asset == coin.toCoinMeta() ? address : nil
        case .unresolved, .lpActionsPaused, .inboundNotFound, .routerNotAvailable, .unsupportedProtocol:
            return nil
        }
    }

    /// Whether the deposit needs an ERC-20 approval before it can settle.
    ///
    /// Informational only — it drives the two-transaction notice on the form.
    /// The approval itself is built at the signing boundary from the
    /// transaction's own recipient, which is what keeps the spender and the
    /// deposit target the same address by construction.
    var requiresApproval: Bool {
        switch self {
        case .inbound(_, _, let requiresApproval):
            return requiresApproval
        case .unresolved, .protocolNative, .lpActionsPaused, .inboundNotFound, .routerNotAvailable,
             .unsupportedProtocol:
            return false
        }
    }

    /// Why the deposit cannot proceed, localized, or nil when nothing is wrong.
    ///
    /// `.unresolved` deliberately says nothing: it is the transient state before
    /// the first answer lands, and a notice there would flash on every open.
    var message: String? {
        switch self {
        case .unresolved, .protocolNative, .inbound:
            return nil
        case .lpActionsPaused(let chain):
            return String(format: "inboundPaused".localized, chain)
        case .inboundNotFound(let chain):
            return String(format: "inboundAddressNotFound".localized, chain)
        case .routerNotAvailable(let chain):
            return String(format: "routerNotAvailable".localized, chain)
        case .unsupportedProtocol:
            return "addLpDestinationUnavailable".localized
        }
    }
}

/// Resolves the L1 destination a liquidity deposit is sent to.
///
/// Resolution happens per deposited asset, at the moment the transaction is
/// made — never once when the form opens. Both properties matter: per asset,
/// because the pool picker reassigns which asset is deposited and the recipient
/// differs between a native transfer (the inbound vault) and an ERC-20 one (the
/// router); at build time with the cache bypassed, because THORChain churns its
/// inbound vaults and a five-minute-old address can already be retired.
///
/// **What this does not do.** It is a build-time check, not a sign-time one:
/// the route can still halt between Continue and the last co-signer. Swaps have
/// `assertSourceChainNotHalted` on the signing path and function calls have no
/// equivalent, so closing this belongs in a gate shared by the whole
/// FunctionCall tail rather than here. It also reads only the per-chain flags
/// the inbound endpoint publishes; THORChain can additionally pause a SINGLE
/// pool's deposits by mimir, which those flags do not express and which would
/// need a separate read.
enum ThorchainLPDestinationResolver {

    /// The inbound-address read this resolution depends on. A closure rather
    /// than a protocol so tests can drive every branch without the network and
    /// without a shared abstraction other flows would have to agree on.
    typealias InboundAddressFetch = (_ bypassCache: Bool) async -> [InboundAddress]

    @MainActor
    static let live: InboundAddressFetch = { bypassCache in
        await ThorchainService.shared.fetchThorchainInboundAddress(bypassCache: bypassCache)
    }

    /// Where a deposit of `coin` into `protocolChain`'s pools must be sent.
    ///
    /// - Parameters:
    ///   - coin: the asset being deposited *right now*. The answer is stamped
    ///     with it so a caller cannot spend it on a different one.
    ///   - protocolChain: whose pools the memo names — `.thorChain` or
    ///     `.mayaChain`.
    ///   - bypassCache: true on the path that builds the transaction.
    @MainActor
    static func resolve(
        depositing coin: Coin,
        into protocolChain: Chain,
        bypassCache: Bool,
        fetch: InboundAddressFetch
    ) async -> LPDepositDestination {
        // The protocol's own asset never leaves its chain: the deposit is a
        // `MsgDeposit` carrying the memo, with no recipient at all.
        if coin.chain == protocolChain {
            return .protocolNative(asset: coin.toCoinMeta())
        }

        // An L1-side deposit is a transfer into the protocol's inbound vault,
        // and only THORChain's vaults are read here. Failing closed rather than
        // reading THORChain's inbound for a MayaChain pool is the whole point:
        // that would send funds to a vault which has never heard of the memo.
        guard protocolChain == .thorChain else {
            return .unsupportedProtocol
        }

        let chainName = ThorchainService.getInboundChainName(for: coin.chain)
        let addresses = await fetch(bypassCache)
        guard let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
            return .inboundNotFound(chain: chainName)
        }

        // An LP add must honour `chain_lp_actions_paused` (the `PauseLP<CHAIN>`
        // mimir) as well as the trading flags — hence `isLPActionsHalted`,
        // which is strictly stricter than the `isTradingHalted` gate the
        // non-LP flows use. Do not relax this one: THORChain rejects an LP add
        // while LP actions are paused, and the funds would be stranded.
        guard !inbound.isLPActionsHalted else {
            return .lpActionsPaused(chain: inbound.chain)
        }

        guard coin.shouldApprove else {
            return .inbound(asset: coin.toCoinMeta(), address: inbound.address, requiresApproval: false)
        }

        // An ERC-20 deposit goes through the router's `depositWithExpiry`, and
        // the router is also the spender the approval must name. Both come from
        // this one address, which is what makes "the approved spender is the
        // deposit target" true by construction rather than by coincidence.
        guard let router = inbound.router, router.isNotEmpty else {
            return .routerNotAvailable(chain: inbound.chain)
        }
        return .inbound(asset: coin.toCoinMeta(), address: router, requiresApproval: true)
    }
}
