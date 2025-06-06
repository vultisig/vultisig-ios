//
//  NavigationMenuButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct NavigationMenuButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Image("MenuIcon")
            .font(.body18MenloBold)
            .foregroundColor(tint)
            .offset(x: -8)
    }
}

#Preview {
    ZStack {
        Background()
        NavigationMenuButton()
    }
}
