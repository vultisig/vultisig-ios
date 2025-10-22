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
        ScrollView {
            content
                .padding(40)
        }
        .crossPlatformToolbar("advanced".localized)
    }
}
#endif
