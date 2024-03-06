    //
    //  BottomBar.swift
    //  VoltixApp
    //

import SwiftUI

struct BottomBar: View {
    let content: String
    let onClick: () -> Void
    var buttondisplay: Bool = true
    
    var body: some View {
        HStack() {
            Spacer()
            if buttondisplay {
                Button(action: onClick) {
                    HStack() {
                        Text(content)
                            .fontWeight(.black)
                        Image(systemName: "chevron.right")
                            .resizable()
                            .frame(width: 10, height: 15)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
    }
}

#Preview {
    BottomBar(content: "CONTINUE", onClick: {})
}
