//
//  SwapInputDetailsView.swift
//  VoltixApp
//

import SwiftUI

struct SwapInputDetailsView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var amount: String = ""
    @State private var gas: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {

            HStack {
                Text("Ethereum")
                    .font(.body20MenloBold)
                    .lineSpacing(30)
                    
                VStack() {
                    Text("23.2")
                        .font(.body20Menlo)
                        .lineSpacing(30)
                        
                }
                .frame(width: 200)
            }
            .padding()
            .frame(height: 56)

            VStack(alignment: .leading) {
                Text("Amount")
                    .font(.body20Menlo)
                    .lineSpacing(30)
                    
                HStack() {
                    TextField("1.0", text: $amount)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.clear)
                        .padding()
                        .frame(width: 200, height: 50, alignment: .center)
                        .background(Color.gray400)
                        .cornerRadius(20)
                    Spacer()
                    Text("MAX")
                        .font(.body20MenloBold)
                        .lineSpacing(30)
                        
                }
                .frame(height: 50)
            }
            .padding()
            .frame(height: 90)
            VStack(alignment: .leading) {
                Text("Gas")
                    .font(.body20Menlo)
                    .lineSpacing(30)
                    
                Spacer()
                HStack() {
                    TextField("auto", text: $gas)
                        .foregroundColor(.clear)
                        .padding()
                        .frame(width: 200, height: 50, alignment: .center)
                        .background(Color.gray400)
                        .cornerRadius(20)
                    Spacer()
                    Text("$4.00")
                        .font(.body20MenloBold)
                        .lineSpacing(30)
                        
                }
                .frame(height: 50)
            }
            .padding()
            .frame(height: 90)
            HStack() {
                VStack(alignment: .leading) {
                    Text("Amount")
                        .font(.body20Menlo)
                        .lineSpacing(30)
                        
                    HStack() {
                        Text("0.1")
                            .font(.title40MontserratLight)
                            .lineSpacing(60)
                            
                        Spacer().frame(width: 30)
                        Text("BTC")
                            .font(.body20Menlo)
                            .lineSpacing(30)
                            
                    }
                }
                Spacer().frame(width: 40)
                VStack(alignment: .leading) {
                    Text("Fees")
                        .font(.body20Menlo)
                        .lineSpacing(30)
                        
                    HStack() {
                        Text("0.001")
                            .font(.title40MontserratLight)
                            .lineSpacing(60)
                            
                        Spacer().frame(width: 30)
                        Text("BTC")
                            .font(.body20Menlo)
                            .lineSpacing(30)
                            
                    }
                }
            }
            .padding()
            VStack(alignment: .leading) {
                Text("Time")
                    .font(.body20Menlo)
                    .lineSpacing(30)
                    
                HStack() {
                    Text("4")
                        .font(.title40MontserratLight)
                        .lineSpacing(60)
                        
                        .frame(width: 80, alignment: .leading)
                    Text("minutes")
                        .font(.body20Menlo)
                        .lineSpacing(30)
                        
                }
            }
            .padding()
            Spacer()
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
    SwapInputDetailsView(presentationStack: .constant([]))
}
