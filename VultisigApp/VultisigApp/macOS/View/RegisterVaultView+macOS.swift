//
//  RegisterVaultView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

#if os(macOS)
import SwiftUI

extension RegisterVaultView {
    var view: some View {
        VStack {
            header
            image
            content
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "registerVault")
    }
}
#endif
