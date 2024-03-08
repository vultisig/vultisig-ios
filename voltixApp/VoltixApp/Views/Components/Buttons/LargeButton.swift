//
//  LargeButton.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import SwiftUI

struct LargeButton: View {
    let content: String;
    let onClick: () -> Void;
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var body: some View {
        Button(action: onClick) {
            VStack() {
                Text(content)
                    .font(.title40MenloBold)
            }
        }
        .frame(width: 240, height: 148)
        //.background(Color(red: 0.96, green: 0.96, blue: 0.96))
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LargeButton(content: "NEW", onClick: {})
}
