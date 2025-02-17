//
//  BackupPasswordSetupView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension BackupSetupView {
    var content: some View {
        ZStack {
            Background()
            main
        }
    }
    
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
    
    var headerMac: some View {
        GeneralMacHeader(title: "backup")
    }
    
    var view: some View {
        VStack {
            animation?.view()
            labels
            Spacer().frame(height: 100)
            buttons
        }
        .padding(.horizontal, 25)
    }
}
#endif
