//
//  OnboardingSummaryView+iOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 13.02.2025.
//

#if os(macOS)
import SwiftUI

extension OnboardingSummaryView {

    var animation: some View {
        animationVM?.view()
            .frame(width: 700, height: 500)
    }
}

#endif
