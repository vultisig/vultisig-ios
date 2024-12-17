//
//  SettingsAdvancedView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

#if os(macOS)
import SwiftUI

extension SettingsAdvancedView {
    var container: some View {
        VStack {
            header
            content
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "advanced")
    }
}
#endif
