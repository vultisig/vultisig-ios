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
        ZStack(alignment: .center) {
            HStack() {
                Button(action: leftAction) {
                    Image(leftIcon)
                        .resizable()
                        .frame(width: 30, height: 30)
                }
                
                .buttonStyle(PlainButtonStyle())
                Spacer()
                Button(action: rightAction) {
                    Image(rightIcon)
                        .resizable()
                        .frame(width: 30, height: 30)
                }
                
                .buttonStyle(PlainButtonStyle())
            } .frame(width: .infinity, height: 130)
            Text(head)
                .font(Font.custom("Menlo", size: 40))
                
        }
        .padding()
        .frame(width: .infinity, height: 119);
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
