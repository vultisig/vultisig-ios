//
//  KeysignView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension KeysignView {
    var container: some View {
        container
            .onAppear {
                setData()
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear(){
                viewModel.stopMessagePuller()
                UIApplication.shared.isIdleTimerDisabled = false
            }
    }
}
#endif
