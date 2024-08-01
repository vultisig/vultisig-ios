//
//  Placement.swift
//  VultisigApp
//
//  Created by Johnny Luo on 25/6/2024.
//

import SwiftUI
enum Placement{
    case topBarLeading
    case topBarTrailing
    case principal

    func getPlacement() -> ToolbarItemPlacement {
#if os(iOS)
        switch self {
        case .topBarLeading:
            return ToolbarItemPlacement.topBarLeading
        case .topBarTrailing:
            return ToolbarItemPlacement.topBarTrailing
        case .principal:
            return ToolbarItemPlacement.principal
        }
#elseif os(macOS)
        switch self {
        case .topBarLeading:
            return ToolbarItemPlacement.navigation
        case .topBarTrailing:
            return ToolbarItemPlacement.automatic
        case .principal:
            return ToolbarItemPlacement.principal
        }
#endif
    }
}


