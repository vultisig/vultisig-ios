//
//  NavigationRefreshButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct NavigationRefreshButton: View {
    var tint: Color = Color.neutral0
    var action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.body18MenloBold)
#if os(iOS)
                .foregroundColor(tint)
#elseif os(macOS)
                .foregroundColor(colorScheme == .light ? .neutral700 : .neutral0)
#endif
        }
    }
}

#Preview {
    ZStack {
        Background()
        NavigationRefreshButton(){}
    }
}
