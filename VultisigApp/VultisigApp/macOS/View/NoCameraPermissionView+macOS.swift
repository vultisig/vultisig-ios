//
//  NoCameraPermissionView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(macOS)
import Cocoa
import SwiftUI

extension NoCameraPermissionView {
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
