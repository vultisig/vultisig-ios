//
//  MenuItem.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct MenuItem: View {
    let content: String;
    let onClick: () -> Void;
    
    var body: some View {
        Button(action: onClick) {
            HStack {
                Spacer()
                Text(content)
                .font(Font.custom("Menlo", size: 35).weight(.bold))
                .lineSpacing(60)
                ;
                Spacer().frame(width: 20)
                Image(systemName: "chevron.right")
                .resizable()
                
                .frame(width: 18, height: 27)
            }
            .padding()
            .frame(height: 70)
        }
    }
}

#Preview {
    MenuItem(
        content: "VAULT RECOVERY",
        onClick: { }
    )
}
