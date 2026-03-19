//
//  ListBottomSection.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct ListBottomSection<Content: View>: View {
    var content: () -> Content
    var body: some View {
        content()
            .padding(.bottom, bottomPadding)
            .padding(.top, 32)
            .background(
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Theme.colors.bgPrimary, location: 0.50),
                        Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0.5), location: 0.85),
                        Gradient.Stop(color: Theme.colors.bgPrimary.opacity(0), location: 1.00)
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 1),
                    endPoint: UnitPoint(x: 0.5, y: 0)
                )
            )
            .edgesIgnoringSafeArea(.bottom)
    }

    var bottomPadding: CGFloat {
        #if os(macOS)
        16
        #else
        0
        #endif
    }
}
