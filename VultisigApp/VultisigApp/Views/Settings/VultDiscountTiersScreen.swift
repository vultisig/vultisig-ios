//
//  VultDiscountTiersScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/10/2025.
//

import SwiftUI

struct VultDiscountTiersScreen: View {
    @ObservedObject var vault: Vault
    
    var body: some View {
        Text("Hello, World!")
    }
}

#Preview {
    VultDiscountTiersScreen(vault: .example)
}
