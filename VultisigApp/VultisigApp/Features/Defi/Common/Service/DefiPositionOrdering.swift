//
//  DefiPositionOrdering.swift
//  VultisigApp
//

import Foundation

/// Shared ordering for DeFi rows whose primary figure is a fiat balance.
///
/// Every caller supplies the exact decimal it paints. Keeping the comparison
/// here makes the main portfolio and the heterogeneous chain-detail sections
/// agree on descending value and deterministic equal-value ties.
enum DefiPositionOrdering {
    static func descending<Element, TieBreak: Comparable>(
        _ elements: [Element],
        value: (Element) -> Decimal,
        tieBreak: (Element) -> TieBreak
    ) -> [Element] {
        elements.sorted { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)
            if lhsValue == rhsValue {
                return tieBreak(lhs) < tieBreak(rhs)
            }
            return lhsValue > rhsValue
        }
    }
}
