//
//  AsyncImageView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-11.
//

#if os(iOS)
import SwiftUI

extension AsyncImageView {
    func imageContainer(_ logoName: String) -> some View {
        ZStack {
            if let image = UIImage(named: logoName) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            } else {
                fallbackText
            }
        }
    }
}
#endif
