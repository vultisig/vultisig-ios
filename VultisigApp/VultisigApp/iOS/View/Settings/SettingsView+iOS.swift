//
//  SettingsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-23.
//

#if os(iOS)
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
        }
    }
    
    var checkUpdateView: some View {
        PhoneCheckUpdateView()
    }
}
#endif
