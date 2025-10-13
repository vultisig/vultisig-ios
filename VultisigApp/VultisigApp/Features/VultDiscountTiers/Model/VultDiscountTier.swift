//
//  VultDiscountTier.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import SwiftUI
import BigInt

enum VultDiscountTier: String, Identifiable, CaseIterable {
    case bronze
    case silver
    case gold
    case platinum
    
    var id: String { rawValue }
    var name: String { rawValue }
    var icon: String { "vult-\(rawValue)" }
    
    var bpsDiscount: Int {
        switch self {
        case .bronze:
            10
        case .silver:
            20
        case .gold:
            30
        case .platinum:
            35
        }
    }
    
    var balanceToUnlock: BigInt {
        switch self {
        case .bronze:
            BigInt(1_000)
        case .silver:
            BigInt(2_500)
        case .gold:
            BigInt(5_000)
        case .platinum:
            BigInt(10_000)
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
        }
    }
    
    var secondaryColor: Color {
        switch self {
        case .bronze, .silver, .gold:
            Color(hex: "3377D9").opacity(0.21)
        case .platinum:
            Color(hex: "4879FD")
        }
    }
}
