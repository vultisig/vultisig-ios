//
//  SettingsAdvancedView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-12-16.
//

#if os(iOS)
import SwiftUI

extension SettingsAdvancedView {
    var container: some View {
        ScrollView {
            content
                .padding(15)
        }
        .navigationTitle(NSLocalizedString("advanced", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
