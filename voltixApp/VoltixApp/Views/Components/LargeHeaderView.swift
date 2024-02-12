//
//  LargeHeaderView.swift
//  VoltixApp
//
//  Created by dev on 08.02.2024.
//

import SwiftUI

struct LargeHeaderView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    let rightIcon: String;
    let leftIcon: String;
    let head: String;
    let leftAction: () -> Void;
    let rightAction: () -> Void;
    let back: Bool;

    var body: some View {
        ZStack(alignment: .center) {
            HStack() {
                Button(action: {
                    if !self.presentationStack.isEmpty {
                        self.presentationStack.removeLast()
                    }
                }) {
                    if back {
                        Image(leftIcon)
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                    else {
                        HStack {
                            Image(leftIcon)
                                .resizable()
                                .frame(width: 30, height: 30)
                            Text("BACK")
                                .font(Font.custom("Menlo", size: 40).weight(.bold))
                                .lineSpacing(60)
                                .foregroundColor(.black)
                        }
                    }
                }
                .foregroundColor(.black)
                .buttonStyle(PlainButtonStyle())
                Spacer()
                Button(action: rightAction) {
                    Image(rightIcon)
                        .resizable()
                        .frame(width: 30, height: 30)
                }
                .foregroundColor(.black)
                .buttonStyle(PlainButtonStyle())
            }
            .frame(width: .infinity, height: 130)
            Text(head)
                .font(Font.custom("Menlo", size: 40))
                .foregroundColor(.black)
        }
        .padding()
        .frame(width: .infinity, height: 119);
    }
}

#Preview {
    LargeHeaderView(
        presentationStack: .constant([]), 
        rightIcon: "QuestionMark",
        leftIcon: "BackArrow",
        head: "START",
        leftAction: {},
        rightAction: {},
        back: true
    );
}
