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
                .foregroundColor(.turquoise600)
            
            Text(NSLocalizedString("devicesOnSameWifi", comment: ""))
                .font(Theme.fonts.caption12)
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
