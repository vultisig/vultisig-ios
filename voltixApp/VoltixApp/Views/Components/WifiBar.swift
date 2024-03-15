//
//  WifiBar.swift
//  VoltixApp
//

import SwiftUI

struct WifiBar: View {
    var body: some View {
        HStack(spacing: 25) {
            Image(systemName: "wifi")
                .font(.title30MenloBlack)
                .foregroundColor(.neutral0)

            Text("Keep devices on same WiFi Network with VOLTIX open")
                .lineSpacing(5)
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
    }
}

#Preview {
    WifiBar()
}
