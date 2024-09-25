//
//  AsyncImageView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(macOS)
import SwiftUI

extension AsyncImageView {
    func imageContainer(_ logoName: String) -> some View {
        ZStack {
            if let image = NSImage(named: logoName) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            } else {
                fallbackText
            }
        }
    }
}
#endif
