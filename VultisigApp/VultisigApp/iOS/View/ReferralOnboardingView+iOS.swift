//
//  ReferredOnboardingView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-04.
//

#if os(iOS)
import SwiftUI

extension ReferredOnboardingView {
    var content: some View {
        ZStack {
            Background()
            shadow
            main
        }
    }
}
#endif
