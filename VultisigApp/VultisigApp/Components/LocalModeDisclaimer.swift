//
//  LocalModeDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-27.
//

import SwiftUI

struct LocalModeDisclaimer: View {
    var body: some View {
        InfoBannerView(
            description: "youAreInLocalMode".localized,
            type: .info,
            leadingIcon: "cloud-off",
            iconColor: Theme.colors.primaryAccent4
        )
    }
}

#Preview {
    LocalModeDisclaimer()
}
