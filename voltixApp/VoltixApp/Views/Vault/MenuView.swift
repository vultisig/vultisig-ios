//
//  MenuView.swift
//  VoltixApp
//

import SwiftUI

struct MenuView: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack() {
          HeaderView(
            rightIcon: "questionmark.circle",
            leftIcon: "chevron.left",
            head: "MENU",
            leftAction: {
                if !self.presentationStack.isEmpty {
                    self.presentationStack.removeLast()
                }
            },
            rightAction: {}
          )
          VStack(alignment: .leading) {
            Text("Choose Vault")
                .font(Font.custom("Menlo", size: 20))
                .lineSpacing(30)
                ;
            HStack() {
                Text("Main Vault")
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                    .lineSpacing(30)
                    ;
                Spacer()
                Image(systemName: "chevron.right")
                    .resizable()
                    
                    .frame(width: 9, height: 15)
                    .rotationEffect(.degrees(90));
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .foregroundColor(.clear)
            .frame(width: .infinity, height: 55)
            .background(Color(red: 0.92, green: 0.92, blue: 0.93))
            .cornerRadius(10);
          }
        Spacer().frame(height: 30)
          MenuItem(
            content: "ADD VAULT",
            onClick: {}
          )
          MenuItem(
            content: "EXPORT VAULT",
            onClick: {}
          )
          MenuItem(
            content: "FORGET VAULT",
            onClick: {}
          )
          MenuItem(
            content: "VAULT RECOVERY",
            onClick: {}
          )
          Spacer()
          VStack {
            Text("VOLTIX APP V1.23")
            .font(Font.custom("Menlo", size: 20).weight(.bold))
            .lineSpacing(30)
            ;
          }
          .frame(width: .infinity, height: 110)
        }
        .padding(.trailing, 20)
        .padding(.leading, 20)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }
}

#Preview {
    MenuView(presentationStack: .constant([]))
}
