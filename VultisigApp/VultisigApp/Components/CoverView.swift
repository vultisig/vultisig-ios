//
//  CoverView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-17.
//

import SwiftUI

/// What the app shows instead of itself while it is leaving, away, or coming
/// back. Named for that job; the screen it draws is shared with the splash and
/// with the lock screen's biometric wait — see ``VultisigBrandScreen``.
struct CoverView: View {
    var body: some View {
        VultisigBrandScreen()
    }
}

#Preview {
    CoverView()
}
