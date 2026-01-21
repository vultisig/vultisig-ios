//
//  WifiBar.swift
//  VultisigApp
//

import SwiftUI

struct WifiInstruction: View {

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Theme.colors.bgButtonPrimary)

            Text(NSLocalizedString("devicesOnSameWifi", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(maxWidth: 250)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ZStack {
        Background()
        WifiInstruction()
    }
}
