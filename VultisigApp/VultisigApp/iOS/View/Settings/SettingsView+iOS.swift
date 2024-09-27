//
//  SettingsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-23.
//

#if os(iOS)
import SwiftUI

extension SettingsView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationTitle(NSLocalizedString("settings", comment: "Settings"))
    }
    
    var main: some View {
        view
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "settings")
            .padding(.bottom, 8)
    }
    
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
