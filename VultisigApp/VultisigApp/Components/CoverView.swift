//
//  CoverView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-17.
//

import SwiftUI

/// What the app shows instead of itself while it is leaving, away, or coming
/// back. Named for that job.
///
/// Given a picture it draws the app's own screen, blurred past reading — and
/// that is a decision about the *return* rather than the departure. What the
/// user sees coming back is the app-switcher card, drawn as they left and zoomed
/// to full screen by the system: a picture, settled before the app has any say
/// in it. A card carrying a different screen than the one behind it cannot be
/// dissolved on the way in, however early the app uncovers — it reads as a cut.
/// A blurred copy keeps the layout, so the same animation reads as the app
/// coming into focus. See ``PrivacyBackdrop`` for how it is taken.
///
/// Given nothing it draws ``VultisigBrandScreen``, which is every case where no
/// picture could be had: the Mac, where there is no app switcher zooming a stale
/// card up and so no transition to solve; the root overlay, which holds no
/// capture of its own; and a capture that failed. That fallback is the more
/// concealing of the two, which is the right way round for one.
struct CoverView: View {

    var backdrop: Image?

    @ViewBuilder
    var body: some View {
        if let backdrop {
            backdrop
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        } else {
            VultisigBrandScreen()
        }
    }
}

#Preview {
    CoverView()
}
