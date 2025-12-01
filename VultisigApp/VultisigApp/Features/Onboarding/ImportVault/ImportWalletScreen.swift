//
//  ImportWalletScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/12/2025.
//

import SwiftUI

struct ImportWalletScreen: View {
    @State var importType: ImportWalletType = .seedphrase
    
    var body: some View {
        Screen {
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
        }
    }
}

#Preview {
    ImportWalletScreen()
}
