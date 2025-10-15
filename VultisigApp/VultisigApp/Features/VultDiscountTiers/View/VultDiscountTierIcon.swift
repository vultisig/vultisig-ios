//
//  VultDiscountTierIcon.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 13/10/2025.
//

import SwiftUI

struct VultDiscountTierIcon: View {
    let tier: VultDiscountTier
    let size: CGFloat
    
    var body: some View {
        Image(tier.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size / 2, height: size / 2)
            .padding(size / 3)
            .background(backgroundView.overlay(overlayView))
    }
    
    var backgroundView: some View {
        borderBgColor.opacity(0.12)
            .mask(Circle())
    }
    
    var overlayView: some View {
        borderBgColor
            .mask(
                Circle()
                    .inset(by: 1)
                    .stroke(lineWidth: 1)
            )
    }
    
    @ViewBuilder
    var borderBgColor: some View {
        switch tier {
        case .bronze, .silver, .gold:
            tier.primaryColor
        case .platinum:
            LinearGradient(
                colors: [
                    tier.primaryColor,
                    tier.secondaryColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    VStack {
        ForEach(VultDiscountTier.allCases) {
            VultDiscountTierIcon(tier: $0, size: 50)
        }
    }
}
