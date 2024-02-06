//
//  LargeButton.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct LargeButton: View {
    let content: String;
    var body: some View {
        Button(action: {

        }) {
          VStack() {
            Text(content)
              .font(Font.custom("Menlo", size: 40).weight(.bold))
              .lineSpacing(60)
              .foregroundColor(.black);
          }
          
        }
        .frame(width: 240, height: 148)
        .cornerRadius(12)
        .foregroundColor(.clear)
        .background(Color(red: 0.96, green: 0.96, blue: 0.96))
    }
}

#Preview {
    LargeButton(content: "NEW")
}
