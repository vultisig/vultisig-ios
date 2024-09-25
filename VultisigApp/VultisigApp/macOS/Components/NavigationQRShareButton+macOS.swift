//
//  NavigationQRShareButton+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-13.
//

#if os(macOS)
import SwiftUI

extension NavigationQRShareButton {
    var container: some View {
        shareLink
    }
}
#endif
