//
//  ImportWalletViewPhone.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-01.
//

#if os(iOS)
import SwiftUI

extension ImportWalletView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("import", comment: "Import title"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
    
    var main: some View {
        view
    }
}
#endif
