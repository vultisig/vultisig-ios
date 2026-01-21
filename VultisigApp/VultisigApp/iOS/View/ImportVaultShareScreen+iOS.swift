//
//  ImportVaultShareScreen+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-01.
//

#if os(iOS)
import SwiftUI

extension ImportVaultShareScreen {
    var content: some View {
        main
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
