//
//  OnboardingView2+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension OnboardingView2 {
    var container: some View {
        content
    }
}

#Preview {
    OnboardingView2(tabIndex: .constant(nil))
}
#endif
