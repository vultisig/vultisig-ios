//
//  WifiBar.swift
//  VultisigApp
//

import SwiftUI

struct WifiInstruction: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.title30MenloUltraLight)
                .foregroundColor(.turquoise600)
            
            Text(NSLocalizedString("devicesOnSameWifi", comment: ""))
                .font(.body12Menlo)
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
