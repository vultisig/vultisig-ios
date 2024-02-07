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
            HeaderView(
                rightIcon: "Refresh",
                leftIcon: "BackArrow",
                head: "SWAP",
                leftAction: {},
                rightAction: {}
            )
            HStack {
                Text("Ethereum")
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                    .lineSpacing(30)
                    .foregroundColor(.black)
                VStack() {
                    Text("23.2")
                        .font(Font.custom("Menlo", size: 20))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                }
                .frame(width: 200)
            }
            .padding()
            .frame(height: 56)

            VStack(alignment: .leading) {
                Text("Amount")
                    .font(Font.custom("Menlo", size: 20))
                    .lineSpacing(30)
                    .foregroundColor(.black)
                HStack() {
                    TextField("1.0", text: $amount)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.clear)
                        .padding()
                        .frame(width: 200, height: 50, alignment: .center)
                        .background(Color(red: 0.92, green: 0.92, blue: 0.93))
                        .cornerRadius(20)
                    Spacer()
                    Text("MAX")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                }
                .frame(height: 50)
            }
            .padding()
            .frame(height: 90)
            VStack(alignment: .leading) {
                Text("Gas")
                    .font(Font.custom("Menlo", size: 20))
                    .lineSpacing(30)
                    .foregroundColor(.black)
                Spacer()
                HStack() {
                    TextField("auto", text: $gas)
                        .foregroundColor(.clear)
                        .padding()
                        .frame(width: 200, height: 50, alignment: .center)
                        .background(Color(red: 0.92, green: 0.92, blue: 0.93))
                        .cornerRadius(20)
                    Spacer()
                    Text("$4.00")
                        .font(Font.custom("Menlo", size: 20).weight(.bold))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                }
                .frame(height: 50)
            }
            .padding()
            .frame(height: 90)
            HStack() {
                VStack(alignment: .leading) {
                    Text("Amount")
                        .font(Font.custom("Menlo", size: 20))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                    HStack() {
                        Text("0.1")
                            .font(Font.custom("Montserrat", size: 40).weight(.light))
                            .lineSpacing(60)
                            .foregroundColor(.black)
                        Spacer().frame(width: 30)
                        Text("BTC")
                            .font(Font.custom("Menlo", size: 20))
                            .lineSpacing(30)
                            .foregroundColor(.black)
                    }
                }
                Spacer().frame(width: 40)
                VStack(alignment: .leading) {
                    Text("Fees")
                        .font(Font.custom("Menlo", size: 20))
                        .lineSpacing(30)
                        .foregroundColor(.black)
                    HStack() {
                        Text("0.001")
                            .font(Font.custom("Montserrat", size: 40).weight(.light))
                            .lineSpacing(60)
                            .foregroundColor(.black)
                        Spacer().frame(width: 30)
                        Text("BTC")
                            .font(Font.custom("Menlo", size: 20))
                            .lineSpacing(30)
                            .foregroundColor(.black)
                    }
                }
            }
            .padding()
            VStack(alignment: .leading) {
                Text("Time")
                    .font(Font.custom("Menlo", size: 20))
                    .lineSpacing(30)
                    .foregroundColor(.black)
                HStack() {
                    Text("4")
                        .font(Font.custom("Montserrat", size: 40).weight(.light))
                        .lineSpacing(60)
                        .foregroundColor(.black)
                        .frame(width: 80, alignment: .leading)
                    Text("minutes")
                        .font(Font.custom("Menlo", size: 20))
                        .lineSpacing(30)
                        .foregroundColor(.black)
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
