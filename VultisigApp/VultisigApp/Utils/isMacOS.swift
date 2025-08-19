//
//  isMacOS.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 18/08/2025.
//

var isMacOS: Bool {
    #if os(macOS)
    return true
#else
    return false
#endif
}
