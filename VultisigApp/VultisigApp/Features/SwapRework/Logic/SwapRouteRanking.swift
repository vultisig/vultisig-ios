//
//  SwapRouteRanking.swift
//  VultisigApp
//
//  Orders the route sheet by what reaches the vault after every fee, gas
//  included when each route's gas is known. The top route is "Best return"; a
//  different, strictly faster route is "Fastest". The sheet can also sort by
//  speed. Only the existing providers are ranked: the sheet never invents one.
//

import Foundation

/// One provider's quote reduced to what the route sheet compares.
struct SwapRouteOption: Equatable, Identifiable {
    /// Stable per provider, so a manual pick survives a refresh.
    let id: String
    let providerName: String
    let providerLogo: String?
    /// Amount of the destination coin the vault receives, net of provider fees.
    let receivedAmount: Decimal
    let receivedFiat: Decimal?
    /// Fees the route charges in fiat, when the provider states them.
    let feesFiat: Decimal?
    /// Estimated seconds to land, when the provider states it.
    let etaSeconds: Int?
    /// Source-chain gas for this route, in fiat, when known.
    var gasFiat: Decimal?

    /// Route fees plus gas: what the row calls "all-in fees".
    var allInFeesFiat: Decimal? {
        guard let feesFiat else { return gasFiat }
        return feesFiat + (gasFiat ?? 0)
    }

    /// What reaches the vault, net of gas, in fiat. Nil without a fiat value.
    var netFiat: Decimal? {
        receivedFiat.map { $0 - (gasFiat ?? 0) }
    }
}

enum SwapRouteSort: String, CaseIterable, Identifiable {
    case bestReturn
    case fastest
    var id: String { rawValue }
}

enum SwapRouteTag: Equatable {
    case bestReturn
    case fastest
}

struct SwapRankedRoute: Equatable, Identifiable {
    let option: SwapRouteOption
    let tags: [SwapRouteTag]
    /// Shortfall against the best route in destination units (0 for the best).
    let shortfall: Decimal
    /// The same shortfall in fiat, net of gas, when both sides have one.
    var shortfallFiat: Decimal?

    var id: String { option.id }
    var isBest: Bool { tags.contains(.bestReturn) }
}

enum SwapRouteRanking {

    /// Highest received amount first. Ties go to the lower fee, then the faster
    /// route, then the provider name, so the order is stable across refreshes.
    /// Options that pay out nothing are dropped: they are not a route.
    static func rank(_ options: [SwapRouteOption]) -> [SwapRankedRoute] {
        let viable = options.filter { $0.receivedAmount > 0 }
        // Net of gas only when every route states its fiat value; otherwise a
        // route without one would win or lose on a missing number.
        let comparesNet = viable.allSatisfy { $0.netFiat != nil }
        let sorted = viable.sorted { isBetter($0, $1, comparesNet: comparesNet) }
        guard let best = sorted.first else { return [] }

        let fastestID = fastestRouteID(in: sorted, bestID: best.id)

        return sorted.map { option in
            var tags: [SwapRouteTag] = []
            if option.id == best.id { tags.append(.bestReturn) }
            if option.id == fastestID { tags.append(.fastest) }
            var shortfallFiat: Decimal?
            if let bestNet = best.netFiat, let net = option.netFiat {
                shortfallFiat = max(bestNet - net, 0)
            }
            return SwapRankedRoute(
                option: option,
                tags: tags,
                shortfall: max(best.receivedAmount - option.receivedAmount, 0),
                shortfallFiat: shortfallFiat
            )
        }
    }

    /// Best return keeps the ranking; fastest orders by stated time, routes
    /// without one last, ties in ranking order.
    static func sorted(_ ranked: [SwapRankedRoute], by sort: SwapRouteSort) -> [SwapRankedRoute] {
        switch sort {
        case .bestReturn:
            return ranked
        case .fastest:
            return ranked.enumerated().sorted { lhs, rhs in
                let lhsEta = lhs.element.option.etaSeconds ?? .max
                let rhsEta = rhs.element.option.etaSeconds ?? .max
                return lhsEta != rhsEta ? lhsEta < rhsEta : lhs.offset < rhs.offset
            }.map(\.element)
        }
    }

    /// The route the form shows: the user's pick while it still quotes,
    /// otherwise the best.
    static func activeRoute(in ranked: [SwapRankedRoute], selectedID: String?) -> SwapRankedRoute? {
        if let selectedID, let picked = ranked.first(where: { $0.id == selectedID }) {
            return picked
        }
        return ranked.first
    }

    private static func isBetter(_ lhs: SwapRouteOption, _ rhs: SwapRouteOption, comparesNet: Bool) -> Bool {
        if comparesNet, let lhsNet = lhs.netFiat, let rhsNet = rhs.netFiat, lhsNet != rhsNet {
            return lhsNet > rhsNet
        }
        if lhs.receivedAmount != rhs.receivedAmount { return lhs.receivedAmount > rhs.receivedAmount }
        let lhsFee = lhs.feesFiat ?? .greatestFiniteMagnitude
        let rhsFee = rhs.feesFiat ?? .greatestFiniteMagnitude
        if lhsFee != rhsFee { return lhsFee < rhsFee }
        let lhsEta = lhs.etaSeconds ?? .max
        let rhsEta = rhs.etaSeconds ?? .max
        if lhsEta != rhsEta { return lhsEta < rhsEta }
        return lhs.providerName < rhs.providerName
    }

    /// "Fastest" only means something when it is a different route from the
    /// best and strictly quicker than it. A route with no stated time never
    /// wins it.
    private static func fastestRouteID(in sorted: [SwapRouteOption], bestID: String) -> String? {
        guard sorted.count > 1 else { return nil }
        let timed = sorted.compactMap { option in option.etaSeconds.map { (option, $0) } }
        guard let fastest = timed.min(by: { $0.1 < $1.1 }), fastest.0.id != bestID else { return nil }
        if let bestEta = sorted.first(where: { $0.id == bestID })?.etaSeconds, bestEta <= fastest.1 {
            return nil
        }
        return fastest.0.id
    }
}
