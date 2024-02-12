//
//  ImportQRCode.swift
//  VoltixApp
//
//  Created by dev on 09.02.2024.
//

import SwiftUI

struct ImportQRCode: View {
    @Binding var presentationStack: Array<CurrentScreen>
    
    var body: some View {
        VStack() {
            HeaderView(
                rightIcon: "QuestionMark",
                leftIcon: "BACTARROW",
                head: "IMPORT",
                leftAction: {
                    self.presentationStack.removeLast()
                },
                rightAction: {}
            )
            VStack {
                Image("Capture")
                    .resizable()
                    .frame(width: 300, height: 300)
            }
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: 0,
                maxHeight: .infinity,
                alignment: .center
            )
            .background(Color(red: 0.12, green: 0.12, blue: 0.12))
        }
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
    }
}

#Preview {
    ImportQRCode(presentationStack: .constant([]))
}
