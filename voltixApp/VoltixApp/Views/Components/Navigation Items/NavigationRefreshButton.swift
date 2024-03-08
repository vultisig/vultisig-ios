//
//  NavigationRefreshButton.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct NavigationRefreshButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Button(action: {
            
        }) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.body18MenloBold)
                .foregroundColor(tint)
        }
    }
}

#Preview {
    ZStack {
        Color.backgroundBlue
            .ignoresSafeArea()
        NavigationRefreshButton()
    }
}
