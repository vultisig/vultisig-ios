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
#if os(iOS)
            .font(.body18MenloBold)
            .foregroundColor(tint)
#elseif os(macOS)
            .font(.body18Menlo)
#endif
    }
}

#Preview {
    ZStack {
        Background()
        NavigationMenuButton()
    }
}
