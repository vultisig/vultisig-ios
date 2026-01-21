//
//  PlatformImageExtension.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-03.
//

#if os(iOS)
import SwiftUI
import CoreImage
import UIKit

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

#elseif os(macOS)
import SwiftUI
import CoreImage
import AppKit

extension NSImage {
    func resized(to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        
        // Set high-quality rendering options
        let context = NSGraphicsContext.current
        context?.imageInterpolation = .high
        context?.shouldAntialias = true
        
        // Clear background to transparent
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        // Draw the image scaled to the new size
        self.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .sourceOver,
                  fraction: 1.0)
        
        return newImage
    }
    
    func compose(with overlayImage: NSImage, rect: CGRect) -> NSImage {
        let compositeImage = NSImage(size: self.size)
        
        compositeImage.lockFocus()
        defer { compositeImage.unlockFocus() }
        
        // Set high-quality rendering options
        let context = NSGraphicsContext.current
        context?.imageInterpolation = .high
        context?.shouldAntialias = true
        
        // Draw the background QR code
        self.draw(in: NSRect(origin: .zero, size: self.size),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        
        // Draw the overlay logo without coordinate flipping
        overlayImage.draw(in: NSRect(x: rect.origin.x,
                                   y: rect.origin.y,
                                   width: rect.size.width,
                                   height: rect.size.height),
                        from: NSRect(origin: .zero, size: overlayImage.size),
                        operation: .sourceOver,
                        fraction: 1.0)
        
        return compositeImage
    }
}
#endif
