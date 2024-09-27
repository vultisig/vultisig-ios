//
//  SettingsDefaultChainView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(iOS)
import SwiftUI

extension SettingsDefaultChainView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("defaultChains", comment: ""))
    }
    
    var main: some View {
        cellContent
    }
}
#endif
