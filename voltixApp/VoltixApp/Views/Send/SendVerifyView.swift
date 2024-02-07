//
//  SendVerifyView.swift
//  VoltixApp
//

import SwiftUI

struct SendVerifyView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
            VStack(alignment: .leading) {
                HeaderView(
                    rightIcon: "",
                    leftIcon: "",
                    head: "VERIFY",
                    leftAction: {},
                    rightAction: {}
                )
                VStack(alignment: .leading) {
                    Text("FROM")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                    Text("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4")
                        .font(Font.custom("Montserrat", size: 13).weight(.medium))
                        .lineSpacing(19.50)
                        .foregroundColor(.black)
                }
                .frame(height: 70)
                VStack(alignment: .leading) {
                    Text("TO")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                    Text("0xF42b6DE07e40cb1D4a24292bB89862f599Ac5B10")
                        .font(Font.custom("Montserrat", size: 13).weight(.medium))
                        .lineSpacing(19.50)
                        .foregroundColor(.black)
                }
                .frame(height: 70)
                HStack() {
                    Text("AMOUNT")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                    Spacer().frame(width: 40)
                    Text("1.0 ETH")
                        .font(Font.custom("Montserrat", size: 40).weight(.light))
                        .lineSpacing(60)
                        .foregroundColor(.black)
                }
                .frame(height: 70)
                VStack(alignment: .leading) {
                    Text("MEMO")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                    Text("TEST")
                        .font(Font.custom("Montserrat", size: 13).weight(.medium))
                        .lineSpacing(19.50)
                        .foregroundColor(.black)
                }
                .frame(height: 70)
                HStack() {
                    Text("GAS")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                    Spacer().frame(width: 40)
                    Text("$4.00")
                        .font(Font.custom("Montserrat", size: 40).weight(.light))
                        .lineSpacing(60)
                        .foregroundColor(.black)
                }
                .frame(height: 70)
                Spacer()
                RadioButtonGroup(
                    items: [
                        "I am sending to the right address",
                        "The amount is correct",
                        "I am not being hacked or phished",
                    ],
                    selectedId: "iPhone 15 Pro, “Matt’s iPhone”, 42"
                ) {
                    selected in print("Selected is: \(selected)")
                }
                BottomBar(
                    content: "COMPLETE",
                    onClick: { }
                )
            }
            .padding(.leading, 20)
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
    SendVerifyView(presentationStack: .constant([]))
}
