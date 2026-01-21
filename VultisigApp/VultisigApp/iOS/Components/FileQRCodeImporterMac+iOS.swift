//
//  FileQRCodeImporterMac+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-13.
//

#if os(iOS)
import SwiftUI

extension FileQRCodeImporterMac {
    var container: some View {
        VStack {
            button

            if let name = fileName {
                fileCell(name)
            }
        }
    }

    func getPreviewImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .padding(.vertical, 18)
    }
}
#endif
