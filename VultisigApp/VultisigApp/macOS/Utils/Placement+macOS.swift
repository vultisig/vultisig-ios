//
//  Placement+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//
#if os(macOS)
import SwiftUI

enum Placement {
    case topBarLeading
    case topBarTrailing
    case principal

    func getPlacement() -> ToolbarItemPlacement {
        switch self {
        case .topBarLeading:
            return ToolbarItemPlacement.navigation
        case .topBarTrailing:
            return ToolbarItemPlacement.automatic
        case .principal:
            return ToolbarItemPlacement.principal
        }
    }
}
#endif
