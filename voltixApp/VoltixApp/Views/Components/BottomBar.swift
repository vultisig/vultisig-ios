//
//  BottomBar.swift
//  VoltixApp
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
                      .fontWeight(.black)
                      .padding(.trailing, 16)
                    Image(systemName: "chevron.right")
                      .resizable()
                      .foregroundColor(.black)
                      .frame(width: 20, height: 15)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.trailing, 16)
    }
}

#Preview {
    BottomBar(content: "CONTINUE", onClick: {})
}
