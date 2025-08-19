//
//  SettingsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-23.
//

#if os(macOS)
import SwiftUI

extension SettingsView {    
    var view: some View {
        ScrollView {
            VStack(spacing: 24) {
                mainSection
                otherSection
                legalSection
                bottomSection
            }
            .padding(15)
            .padding(.top, 30)
            .padding(.horizontal, 25)
        }
    }
    
    var checkUpdateView: some View {
        MacCheckUpdateView()
    }
}
#endif
