//
//  OnboardingView3+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension OnboardingView3 {
    var container: some View {
        content
    }
}

#Preview {
    OnboardingView3(tabIndex: .constant(nil))
}
#endif
