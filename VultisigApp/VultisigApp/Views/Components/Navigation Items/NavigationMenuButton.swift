//
//  NavigationMenuButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct NavigationMenuButton: View {
    var tint: Color = Color.neutral0
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Image("MenuIcon")
            .font(.body18MenloBold)
#if os(iOS)
                .foregroundColor(tint)
#elseif os(macOS)
                .foregroundColor(colorScheme == .light ? .neutral700 : .neutral0)
#endif
    }
}

#Preview {
    ZStack {
        Background()
        NavigationMenuButton()
    }
}
