//
//  NavigationHelpButton.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct NavigationHelpButton: View {
    var tint: Color = Color.neutral0
    
    var body: some View {
        Button(action: {
            
        }) {
            Image(systemName: "questionmark.circle")
                .font(.body18MenloBold)
                .foregroundColor(tint)
        }
    }
}

#Preview {
    ZStack {
        Color.backgroundBlue
            .ignoresSafeArea()
        NavigationHelpButton()
    }
}
