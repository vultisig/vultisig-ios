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
        do {
            if let url = urls.first {
                let _ = url.startAccessingSecurityScopedResource()
                fileName = url.lastPathComponent
                
                let imageData = try Data(contentsOf: url)
                if let nsImage = NSImage(data: imageData) {
                    selectedImage = nsImage
                }
                isButtonEnabled = true
            }
        } catch {
            print(error)
        }
    }
}
#endif
