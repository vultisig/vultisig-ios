//
//  HomeRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/12/2025.
//

import SwiftUI

struct HomeRouteBuilder {
    
    @ViewBuilder
    func buildHome(showingVaultSelector: Bool) -> some View {
        HomeScreen(showingVaultSelector: showingVaultSelector)
    }
    
}
