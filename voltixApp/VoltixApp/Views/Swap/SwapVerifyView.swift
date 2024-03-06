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
                        .font(.body20MenloBold)
                        .lineSpacing(30)
                        
                    Text("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4")
                        .font(.body13MontserratMedium)
                        .lineSpacing(19.50)
                        
                }
                .frame(height: 70)
                VStack(alignment: .leading) {
                    Text("TO")
                        .font(.body20MenloBold)
                        .lineSpacing(30)
                        
                    Text("0xF42b6DE07e40cb1D4a24292bB89862f599Ac5B10")
                        .font(.body13MontserratMedium)
                        .lineSpacing(19.50)
                        
                }
                .frame(height: 70)
                HStack() {
                    Text("AMOUNT")
                        .font(.body20MenloBold)
                        .lineSpacing(30)
                        
                    Spacer().frame(width: 40)
                    Text("1.0 ETH")
                        .font(.title40MontserratLight)
                        .lineSpacing(60)
                        
                }
                .frame(height: 70)
                VStack(alignment: .leading) {
                    Text("MEMO")
                        .font(.body20MenloBold)
                        .lineSpacing(30)
                        
                    Text("TEST")
                        .font(.body13MontserratMedium)
                        .lineSpacing(19.50)
                        
                }
                .frame(height: 70)
                HStack() {
                    Text("GAS")
                        .font(.body20MenloBold)
                        .lineSpacing(30)
                        
                    Spacer().frame(width: 40)
                    Text("$4.00")
                        .font(.title40MontserratLight)
                        .lineSpacing(60)
                        
                }
                .frame(height: 70)
                Spacer()
                
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
