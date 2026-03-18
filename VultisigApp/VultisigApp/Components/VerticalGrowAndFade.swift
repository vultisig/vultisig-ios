//
//  VerticalGrowAndFade.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/09/2025.
//

import SwiftUI

extension AnyTransition {
    static var verticalGrowAndFade: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.interpolatingSpring(duration: 0.3).delay(0.3)),
            removal: .opacity.animation(.interpolatingSpring(duration: 0.25)),
        )
    }
}
