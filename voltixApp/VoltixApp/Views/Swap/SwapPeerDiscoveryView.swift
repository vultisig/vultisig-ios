//
//  SwapPeerDiscoveryView.swift
//  VoltixApp
//

import SwiftUI

struct SwapPeerDiscoveryView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack {

          Text("VERIFY ALL DETAILS")
                .font(.body24MontserratMedium)
                .lineSpacing(36)
            
          Spacer().frame(height: 80)
          Text("iPhone 15 Pro\nMatt’s iPhone")
                .font(.body24MontserratMedium)
                .lineSpacing(12)
            
          Spacer().frame(height: 20)
          Text("42")
                .font(.title80MontserratLight)
                .lineSpacing(120)
            
          Spacer()
          WifiBar()
          Spacer().frame(height: 70 )
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
    }
}

#Preview {
    SwapPeerDiscoveryView(presentationStack: .constant([]))
}
