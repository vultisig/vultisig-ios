//
//  FastBackupVaultOverview+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

#if os(iOS)
import SwiftUI

extension FastBackupVaultOverview {
    var container: some View {
        content
            .navigationBarBackButtonHidden(true)
    }
    
    var textTabView: some View {
        text
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
    
    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 100)
    }
}
#endif
