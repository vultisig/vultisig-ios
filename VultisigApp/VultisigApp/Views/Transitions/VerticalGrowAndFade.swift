//
//  VerticalGrowAndFade.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/09/2025.
//

import SwiftUI

struct VerticalGrowAndFadeViewModifier: ViewModifier {
    let y: CGFloat
    let opacity: Double
    let anchor: UnitPoint
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: y, anchor: anchor)
            .opacity(opacity)
            .clipped()
    }
}

extension AnyTransition {
    static var verticalGrowAndFade: AnyTransition {
        .modifier(
            active: VerticalGrowAndFadeViewModifier(y: 0.0, opacity: 0.0, anchor: .top),
            identity: VerticalGrowAndFadeViewModifier(y: 1.0, opacity: 1.0, anchor: .top)
        )
    }
}
