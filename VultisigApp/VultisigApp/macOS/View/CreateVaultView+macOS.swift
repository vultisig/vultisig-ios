//
//  CreateVaultView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(macOS)
import SwiftUI

extension CreateVaultView {
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
}
#endif