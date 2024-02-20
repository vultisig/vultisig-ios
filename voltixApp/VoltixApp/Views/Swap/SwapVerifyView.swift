//
//  SwapVerifyView.swift
//  VoltixApp
//

import SwiftUI

struct SwapVerifyView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
            VStack(alignment: .leading) {

                VStack(alignment: .leading) {
                    Text("FROM")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        
                    Text("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4")
                        .font(Font.custom("Montserrat", size: 13).weight(.medium))
                        .lineSpacing(19.50)
                        
                }
                .frame(height: 70)
                VStack(alignment: .leading) {
                    Text("TO")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        
                    Text("0xF42b6DE07e40cb1D4a24292bB89862f599Ac5B10")
                        .font(Font.custom("Montserrat", size: 13).weight(.medium))
                        .lineSpacing(19.50)
                        
                }
                .frame(height: 70)
                HStack() {
                    Text("AMOUNT")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        
                    Spacer().frame(width: 40)
                    Text("1.0 ETH")
                        .font(Font.custom("Montserrat", size: 40).weight(.light))
                        .lineSpacing(60)
                        
                }
                .frame(height: 70)
                VStack(alignment: .leading) {
                    Text("MEMO")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        
                    Text("TEST")
                        .font(Font.custom("Montserrat", size: 13).weight(.medium))
                        .lineSpacing(19.50)
                        
                }
                .frame(height: 70)
                HStack() {
                    Text("GAS")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        
                    Spacer().frame(width: 40)
                    Text("$4.00")
                        .font(Font.custom("Montserrat", size: 40).weight(.light))
                        .lineSpacing(60)
                        
                }
                .frame(height: 70)
                Spacer()
                RadioButtonGroup(
                    items: [
                        "I am sending to the right address",
                        "The amount is correct",
                        "I am not being hacked or phished",
                    ],
                    selectedId: "I am sending to the right address"
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
    SwapVerifyView(presentationStack: .constant([]))
}
