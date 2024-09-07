//
//  NoCameraPermissionView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(iOS)
import SwiftUI

extension NoCameraPermissionView {
    func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}
#endif
