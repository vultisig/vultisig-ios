//
//  CoverView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-17.
//

import SwiftUI

/// The privacy cover: what the app shows instead of itself while it is leaving,
/// away, or coming back.
///
/// **Static, unlike the splash.** `VultisigLogoAnimation` builds its Rive model
/// in `onLoad`, which runs after the first render — so on a cover that goes up
/// as the app is being backgrounded there is a frame of bare gradient, then a
/// logo popping in and starting an animation nobody is going to watch. The
/// gradient is opaque either way, so this is about how it looks rather than what
/// it hides. `WelcomeView` keeps the animation, because a launch splash is a
/// screen the user is actually looking at.
struct CoverView: View {
    var body: some View {
        ZStack {
            VultisigLogoAnimation(isStatic: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PrimaryBackgroundWithGradient())
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

#Preview {
    CoverView()
}
