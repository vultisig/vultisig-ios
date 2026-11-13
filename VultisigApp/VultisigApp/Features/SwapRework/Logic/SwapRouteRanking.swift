//
//  SwapRouteRanking.swift
//  VultisigApp
//
//  Orders the route sheet by what reaches the vault. The top route is "Best
//  price"; a different route that is strictly faster is tagged "Fastest". Only
//  the existing providers are ranked: the sheet never invents a route.
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
}

enum SwapRouteTag: Equatable {
    case bestPrice
    case fastest
}

struct SwapRankedRoute: Equatable, Identifiable {
    let option: SwapRouteOption
    let tags: [SwapRouteTag]
    /// Shortfall against the best route in destination units (0 for the best).
    let shortfall: Decimal

    var id: String { option.id }
}

enum SwapRouteRanking {

    /// Highest received amount first. Ties go to the lower fee, then the faster
    /// route, then the provider name, so the order is stable across refreshes.
    /// Options that pay out nothing are dropped: they are not a route.
    static func rank(_ options: [SwapRouteOption]) -> [SwapRankedRoute] {
        let viable = options.filter { $0.receivedAmount > 0 }
        let sorted = viable.sorted(by: isBetter)
        guard let best = sorted.first else { return [] }

        let fastestID = fastestRouteID(in: sorted, bestID: best.id)

        return sorted.map { option in
            var tags: [SwapRouteTag] = []
            if option.id == best.id { tags.append(.bestPrice) }
            if option.id == fastestID { tags.append(.fastest) }
            return SwapRankedRoute(
                option: option,
                tags: tags,
                shortfall: best.receivedAmount - option.receivedAmount
            )
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

    private static func isBetter(_ lhs: SwapRouteOption, _ rhs: SwapRouteOption) -> Bool {
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
