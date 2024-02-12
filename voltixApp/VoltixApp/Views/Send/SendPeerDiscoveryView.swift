//
//  SendPeerDiscoveryView.swift
//  VoltixApp
//

import SwiftUI

struct SendPeerDiscoveryView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack() {
            HeaderView(
                rightIcon: "QuestionMark",
                leftIcon: "BackArrow",
                head: "SEND",
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
            RadioButtonGroup(
                items: [
                    "iPhone 15 Pro, “Matt’s iPhone”, 42",
                    "iPhone 13, “Matt’s iPhone 13”, 13",
                ],
                selectedId: "iPhone 15 Pro, “Matt’s iPhone”, 42"
            ) {
                selected in print("Selected is: \(selected)")
            }
            Spacer()
            WifiBar()
            BottomBar(
                content: "CONTINUE",
                onClick: { }
            )
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
    SendPeerDiscoveryView(presentationStack: .constant([]))
}
