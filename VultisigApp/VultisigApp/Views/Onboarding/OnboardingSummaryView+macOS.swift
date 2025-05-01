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
        ZStack {
            if kind == .secure {
                SecureBackupGuideAnimation(vault: vault)
            } else {
                animationVM?.view()
            }
        }
        .frame(width: 500, height: 400)
    }
}

#endif
