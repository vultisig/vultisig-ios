//
//  SettingsDefaultChainView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI

extension SettingsDefaultChainView {
    var container: some View {
        content
    }
    
    var main: some View {
        cellContent
    }
}
#endif
