//
//  ImportWalletScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/12/2025.
//

import SwiftUI

struct ImportWalletScreen: View {
    @State var importType: ImportWalletType = .vault
    
    var body: some View {
        Screen(title: "importVault".localized) {
            #if DEBUG
            VStack {
                FilledSegmentedControl(
                    selection: $importType,
                    options: ImportWalletType.allCases
                )
                
                Group {
                    switch importType {
                    case .vault:
                        ImportWalletView()
                    case .seedphrase:
                        ImportSeedphraseView()
                    }
                }
                .transition(.opacity)
                .animation(.interpolatingSpring, value: importType)
                .frame(maxHeight: .infinity)
            }
            #else
            ImportWalletView()
            #endif
        }
    }
}

#Preview {
    ImportWalletScreen()
}
