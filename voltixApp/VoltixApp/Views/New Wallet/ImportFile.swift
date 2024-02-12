//
//  ImportFile.swift
//  VoltixApp
//
//  Created by dev on 09.02.2024.
//

import SwiftUI

struct ImportFile: View {
    @Binding var presentationStack: Array<CurrentScreen>

    var body: some View {
        VStack() {
            HeaderView(
                rightIcon: "questionmark.circle", 
                leftIcon: "chevron.left",
                head: "IMPORT",
                leftAction: {
                    self.presentationStack.removeLast()
                },
                rightAction: {}
            )
            FileItem(
                icon: "MinusCircle",
                filename: "voltix-vault-share-jun2024.txt"
            )
            Spacer()
            BottomBar(content: "CONTINUE", onClick: {
                self.presentationStack.append(.vaultSelection)
            })
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
    ImportFile()
}
