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
    
    @State var animate: Bool = false
    @State var enableTransition: Bool = true
    
    var body: some View {
        Button {
            handleTap()
        } label: {
            Image(systemName: "arrow.clockwise.circle")
                .font(.body18MenloBold)
                .foregroundColor(tint)
                .rotationEffect(.degrees(animate ? 360 : 0))
                .animation(enableTransition ? .easeInOut(duration: 1) : nil, value: animate)
        }
    }
    
    private func handleTap() {
        animate = true
        enableTransition = true
        action()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            enableTransition = false
            animate = false
        }
    }
}

#Preview {
    ZStack {
        Background()
        NavigationRefreshButton(){}
    }
}
