//
//  SwapPeerDiscoveryView.swift
//  VoltixApp
//

import SwiftUI

struct SwapPeerDiscoveryView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack {
          HeaderView(
            rightIcon: "QuestionMark",
            leftIcon: "BackArrow",
            head: "PAIR",
            leftAction: {
                if !self.presentationStack.isEmpty {
                    self.presentationStack.removeLast()
                }
            },
            rightAction: {}
          )
          Text("VERIFY ALL DETAILS")
            .font(Font.custom("Montserrat", size: 24).weight(.medium))
            .lineSpacing(36)
            .foregroundColor(.black)
          Spacer().frame(height: 80)
          Text("iPhone 15 Pro\nMatt’s iPhone")
            .font(Font.custom("Montserrat", size: 24).weight(.medium))
            .lineSpacing(12)
            .foregroundColor(.black)
          Spacer().frame(height: 20)
          Text("42")
            .font(Font.custom("Montserrat", size: 80).weight(.light))
            .lineSpacing(120)
            .foregroundColor(.black)
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
