//
//  isIPadOS.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/09/2025.
//

#if os(iOS)
import SwiftUI
#endif

var isIPadOS: Bool {
    #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
    #else
        return false
    #endif
}
