//
//  SendInputDetailsView.swift
//  VoltixApp
//

import SwiftUI

struct SendInputDetailsView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    @State private var toAddress: String = ""
    @State private var amount: String = ""
    @State private var memo: String = ""
    @State private var gas: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            HeaderView(
                rightIcon: "",
                leftIcon: "BackArrow",
                head: "SEND",
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
                Text("To")
                    .font(Font.custom("Menlo", size: 20))
                    .lineSpacing(30)
                    .foregroundColor(.black)
                TextField("0x0cb1D4a24292bB89862f599Ac5B10F42b6DE07e4", text: $toAddress) // <1>, <2>
                    .padding()
                    .background(Color(red: 0.92, green: 0.92, blue: 0.93))
                    .cornerRadius(10)
            }
            .padding()
            .frame(height: 90)

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
                Text("Memo")
                    .font(Font.custom("Menlo", size: 20))
                    .lineSpacing(30)
                    .foregroundColor(.black)
                TextField("test", text: $memo) // <1>, <2>
                    .padding()
                    .background(Color(red: 0.92, green: 0.92, blue: 0.93))
                    .cornerRadius(10)
            }
            .padding()
            .frame(height: 90)
            Spacer()
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
            Spacer().frame(height: 30)
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
    SendInputDetailsView(presentationStack: .constant([]))
}
