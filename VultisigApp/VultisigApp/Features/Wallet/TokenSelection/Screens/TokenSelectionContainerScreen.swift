//
//  TokenSelectionContainerScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 26/09/2025.
//

import SwiftUI

struct TokenSelectionContainerScreen: View {
    let vault: Vault
    let chain: Chain
    @Binding var isPresented: Bool

    @State var showTokenSelection: Bool = true

    var body: some View {
        ZStack {
            Group {
                if showTokenSelection {
                    TokenSelectionScreen(
                        vault: vault,
                        chain: chain,
                        isPresented: $isPresented,
                        onCustomToken: toggleSheet
                    )
                } else {
                    CustomTokenScreen(
                        vault: vault,
                        chain: chain,
                        isPresented: $isPresented,
                        onClose: toggleSheet
                    )
                }
            }
        }
        .background(Theme.colors.bgPrimary)
        .applySheetSize()
        .sheetStyle(padding: 0)
    }

    private func toggleSheet() {
        withAnimation { showTokenSelection.toggle() }
    }
}

#Preview {
    TokenSelectionContainerScreen(
        vault: .example,
        chain: .bitcoin,
        isPresented: .constant(true)
    )
}
