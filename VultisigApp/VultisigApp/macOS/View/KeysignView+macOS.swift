//
//  KeysignView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension KeysignView {
    var container: some View {
        content
            .onAppear {
                setData()
            }
            .onDisappear(){
                viewModel.stopMessagePuller()
            }
    }
}
#endif
