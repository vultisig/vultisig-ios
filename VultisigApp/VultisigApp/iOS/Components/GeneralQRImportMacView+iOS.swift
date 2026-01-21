//
//  GeneralQRImportMacView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-13.
//

#if os(iOS)
import SwiftUI

extension GeneralQRImportMacView {
    func setValues(_ urls: [URL]) {
        do {
            if let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                fileName = url.lastPathComponent
                
                let imageData = try Data(contentsOf: url)
                if let uiImage = UIImage(data: imageData) {
                    selectedImage = uiImage
                }
                isButtonEnabled = true
            }
        } catch {
            print(error)
        }
    }
}
#endif
