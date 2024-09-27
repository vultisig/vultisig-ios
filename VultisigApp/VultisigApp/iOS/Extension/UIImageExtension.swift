//
//  UIImageExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-03.
//

#if os(iOS)
import SwiftUI

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
