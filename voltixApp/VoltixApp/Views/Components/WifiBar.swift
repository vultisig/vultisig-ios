//
//  WifiBar.swift
//  VoltixApp
//

import SwiftUI

struct WifiBar: View {
    var body: some View {
        HStack(spacing: 25) {
            ZStack {
                Image(systemName: "wifi")
                    .font(.title30MenloBlack)
                    .foregroundColor(.neutral0)
            }
            .frame(width: 36, height: 29)
            Text("Keep devices on same WiFi Network with VOLTIX open")
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
                .lineSpacing(5)
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
        }

        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
        .frame(height: 71)
    }
}

#Preview {
    WifiBar()
}
