//
//  VultDiscountTier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import SwiftUI
import BigInt

enum VultDiscountTier: String, Identifiable, CaseIterable, Comparable {
    case bronze
    case silver
    case gold
    case platinum
    case diamond
    case ultimate

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var icon: ImageResource {
        switch self {
        case .bronze:
            .vultBronze
        case .silver:
            .vultSilver
        case .gold:
            .vultGold
        case .platinum:
            .vultPlatinum
        case .diamond:
            .vultDiamond
        case .ultimate:
            .vultUltimate
        }
    }

    var bpsDiscount: Int {
        switch self {
        case .bronze:
            5
        case .silver:
            10
        case .gold:
            20
        case .platinum:
            25
        case .diamond:
            35
        case .ultimate:
            .max
        }
    }

    var balanceToUnlock: Decimal {
        switch self {
        case .bronze:
            1_500
        case .silver:
            3_000
        case .gold:
            7_500
        case .platinum:
            15_000
        case .diamond:
            100_000
        case .ultimate:
            1_000_000
        }
    }

    var primaryColor: Color {
        switch self {
        case .bronze:
            Color(hex: "DB5727")
        case .silver:
            Color(hex: "C9D6E8")
        case .gold:
            Color(hex: "FFC25C")
        case .platinum:
            Color(hex: "33E6BF")
        case .diamond:
            Color(hex: "00CCFF")
        case .ultimate:
            Color(hex: "0F4594")
        }
    }

    var secondaryColor: Color {
        switch self {
        case .bronze:
            Color(hex: "993B1F")
        case .silver:
            Color(hex: "7D8B9E")
        case .gold:
            Color(hex: "997437")
        case .platinum:
            Color(hex: "4879FD")
        case .diamond:
            Color(hex: "9747FF")
        case .ultimate:
            Color(hex: "E8B762")
        }
    }

    /// Localized perk-pill copy driven by the tier's discount data.
    /// `.ultimate`'s `bpsDiscount` is `Int.max` (a sentinel), so it renders the
    /// fee-waiver copy instead of a numeric bps value.
    var discountPerkText: String {
        switch self {
        case .ultimate:
            "noFee".localized
        default:
            String(format: "vultDiscount".localized, bpsDiscount)
        }
    }

    /// Returns the tier matching the given BPS discount, or nil if no match
    static func from(bpsDiscount: Int) -> VultDiscountTier? {
        allCases.first { $0.bpsDiscount == bpsDiscount }
    }

    /// Whether `tier` is unlockable given the vault's currently `active` tier.
    /// Tiers are ranked by `balanceToUnlock` ascending. With no active tier the
    /// user can buy into any tier; otherwise only tiers strictly above the
    /// active one are unlockable — at-or-below tiers are already covered.
    static func canUnlock(_ tier: VultDiscountTier, active: VultDiscountTier?) -> Bool {
        let ranked = allCases.sorted { $0.balanceToUnlock < $1.balanceToUnlock }
        guard let active, let activeIndex = ranked.firstIndex(of: active) else {
            return true
        }
        let tierIndex = ranked.firstIndex(of: tier) ?? 0
        return tierIndex > activeIndex
    }

    /// Ordering follows the `CaseIterable` declaration order
    /// (bronze < silver < gold < platinum < diamond < ultimate), which is the
    /// ascending unlock order. Used by the shared tier gate to compare a
    /// resolved tier against a required minimum.
    static func < (lhs: VultDiscountTier, rhs: VultDiscountTier) -> Bool {
        guard let lhsIndex = allCases.firstIndex(of: lhs),
              let rhsIndex = allCases.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}
