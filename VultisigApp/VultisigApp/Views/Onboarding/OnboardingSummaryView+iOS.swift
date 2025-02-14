//
//  OnboardingSummaryView+iOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 13.02.2025.
//

#if os(iOS)
import SwiftUI

extension OnboardingSummaryView {

    var animation: some View {
        animationVM?.view()
    }
}

#endif
