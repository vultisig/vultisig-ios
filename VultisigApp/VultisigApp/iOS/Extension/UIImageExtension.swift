//
//  UIImageExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-03.
//

#if os(iOS)
import SwiftUI
import CoreImage

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    func compose(with overlayImage: UIImage, rect: CGRect) -> UIImage {
        let backgroundImage = self

        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)

        let areaSize = CGRect(x: 0, y: 0, width: backgroundImage.size.width, height: backgroundImage.size.height)
        backgroundImage.draw(in: areaSize)

        overlayImage.draw(in: rect)

        guard let mergedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            return self
        }

        UIGraphicsEndImageContext()
        return mergedImage
    }
}
#endif
