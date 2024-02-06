//
//  WifiBar.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct WifiBar: View {
    var body: some View {
        HStack(spacing: 25) {
              ZStack() {
                  Image("Wifi")
                  .resizable()
                  .frame(width: 36, height: 29)
              }
              .frame(width: 36, height: 29)
              Text("Keep devices on same WiFi Network with VOLTIX open")
              .font(Font.custom("Montserrat", size: 24).weight(.medium))
              .lineLimit(nil)
              .fixedSize(horizontal: false, vertical: /*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
              .lineSpacing(5)
              .foregroundColor(.black)
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
        .frame(width: 430, height: 71);
    }
}

#Preview {
    WifiBar()
}
