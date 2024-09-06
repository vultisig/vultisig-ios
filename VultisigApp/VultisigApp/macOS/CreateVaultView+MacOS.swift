//
//  CreateVaultView+MacOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

import SwiftUI

#if os(macOS)
extension CreateVaultView {
    var main: some View {
        VStack {
            headerMac
            view
        }
    }
}
#endif
