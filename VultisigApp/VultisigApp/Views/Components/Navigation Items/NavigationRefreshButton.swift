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
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise.circle")
#if os(iOS)
                .font(.body18MenloBold)
                .foregroundColor(tint)
#elseif os(macOS)
                .font(.body18Menlo)
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
