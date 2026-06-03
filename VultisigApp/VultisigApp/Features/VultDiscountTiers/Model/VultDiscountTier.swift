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
    var icon: String { "vult-\(rawValue)" }

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
            Color(hex: "9747FF")
        case .ultimate:
            .black
        }
    }

    var secondaryColor: Color {
        switch self {
        case .bronze, .silver, .gold:
            Color(hex: "3377D9").opacity(0.21)
        case .platinum:
            Color(hex: "4879FD")
        case .diamond:
            Color(hex: "00CCFF")
        case .ultimate:
            .clear
        }
    }

    /// Returns the tier matching the given BPS discount, or nil if no match
    static func from(bpsDiscount: Int) -> VultDiscountTier? {
        allCases.first { $0.bpsDiscount == bpsDiscount }
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
