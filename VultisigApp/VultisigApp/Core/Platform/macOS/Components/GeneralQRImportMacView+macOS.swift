//
//  GeneralQRImportMacView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-13.
//

#if os(macOS)
import SwiftUI

extension GeneralQRImportMacView {
    func setValues(_ urls: [URL]) {
        guard let url = urls.first else { return }

        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else { return }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        fileName = url.lastPathComponent
        isButtonEnabled = true

        if let image = NSImage(contentsOf: url) {
            selectedImage = image
        }
    }
}
#endif
