//
//  FileQRCodeImporterMac+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-13.
//

#if os(macOS)
import SwiftUI

extension FileQRCodeImporterMac {
    var container: some View {
        VStack {
            button

            if let name = fileName {
                fileCell(name)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isUploading) { providers -> Bool in
            OnDropQRUtils.handleFileQRCodeImporterMacDrop(providers: providers) { result in
                handleFileImport(result)
            }
            return true
        }
    }

    func getPreviewImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(.vertical, 18)
    }
}
#endif
