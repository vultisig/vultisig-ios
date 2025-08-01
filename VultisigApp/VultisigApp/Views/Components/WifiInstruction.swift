//
//  WifiBar.swift
//  VultisigApp
//

import SwiftUI

struct WifiInstruction: View {
    @Environment(\.theme) var theme
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.title30MenloUltraLight)
                .foregroundColor(.turquoise600)
            
            Text(NSLocalizedString("devicesOnSameWifi", comment: ""))
                .font(theme.fonts.caption12)
                .foregroundColor(.neutral0)
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
