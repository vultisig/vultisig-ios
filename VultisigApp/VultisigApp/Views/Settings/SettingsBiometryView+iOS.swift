//
//  SettingsBiometryView+iOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.10.2024.
//

#if os(iOS)
import SwiftUI

extension SettingsBiometryView {
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("enableBiometrics", comment: ""))
    }
}
#endif
