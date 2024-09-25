//
//  VaultDetailScanButton+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension VaultDetailScanButton {
    var content: some View {
        Button {
            showSheet.toggle()
        } label: {
            label
        }
    }
}
#endif
