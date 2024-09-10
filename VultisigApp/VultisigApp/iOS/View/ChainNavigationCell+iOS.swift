//
//  ChainNavigationCell+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-10.
//

#if os(iOS)
import SwiftUI

extension ChainNavigationCell {
    func copyAddress() {
        showAlert = true
        
        let pasteboard = UIPasteboard.general
        pasteboard.string = group.address
    }
}
#endif
