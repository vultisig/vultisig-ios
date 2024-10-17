//
//  SettingsBiometryView+macOS.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.10.2024.
//

#if os(macOS)
import SwiftUI

extension SettingsBiometryView {

    var content: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                headerMac
                main
            }
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: NSLocalizedString("enableBiometrics", comment: ""))
            .padding(.bottom, 8)
    }
}
#endif
