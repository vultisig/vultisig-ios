//
//  BottomBar.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct BottomBar: View {
    let content: String;
    let onClick: () -> Void;
    let buttondisplay: Bool;
    
    init(
        content: String,
        onClick: @escaping () -> Void,
        buttondisplay: Bool = true
    ) {
        self.content = content;
        self.onClick = onClick;
        self.buttondisplay = buttondisplay;
    }
    
    var body: some View {
        HStack() {
            Spacer()
            if buttondisplay {
                Button(action: onClick) {
                  HStack() {
                    Text(content)
                      .lineSpacing(60)
                      .font(Font.custom("Menlo", size: 40).weight(.black))
                      .foregroundColor(.black)
                      .padding(.trailing, 16)
                    Image(systemName: "chevron.right")
                      .resizable()
                      .foregroundColor(.black)
                      .frame(width: 20, height: 30)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.trailing, 16)
        .frame(width: .infinity, height: 70)
    }
}

#Preview {
    BottomBar(content: "CONTINUE", onClick: {})
}
