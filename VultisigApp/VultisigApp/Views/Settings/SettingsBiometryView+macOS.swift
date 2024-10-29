//
//  SettingsBiometryView+iOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 29.10.2024.
//

#if os(macOS)
import SwiftUI

extension SettingsBiometryView {

    var main: some View {
        VStack {
            headerMac
            view
                .padding(.bottom, 30)
                .padding(.horizontal, 40)
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "enableBiometrics")
    }
}

#endif
