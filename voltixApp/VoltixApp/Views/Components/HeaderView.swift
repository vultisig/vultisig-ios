//
//  HeaderView.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct HeaderView: View {
    let rightIcon: String;
    let leftIcon: String;
    let head: String;
    let leftAction: () -> Void;
    let rightAction: () -> Void;
    
    var body: some View {
        HStack() {
            Button(action: leftAction) {
                Image(systemName: "chevron.left")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Color.blue) // Adapts well in both light and dark mode
                    .frame(width: 32, height: 30)
            }
            .frame(width: 30, height: 30)
            Spacer()
            Text(head)
                .font(Font.custom("Menlo", size: 40))
            Spacer()
            Button(action: rightAction) {
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Color.blue) // Adapts well in both light and dark mode
                    .frame(width: 32, height: 30)
            }
            .frame(width: 30, height: 30)
        }.padding()
    }
}

#Preview {
    HeaderView(
        rightIcon: "QuestionMark",
        leftIcon: "BackArrow",
        head: "START",
        leftAction: {},
        rightAction: {}
    )
}
