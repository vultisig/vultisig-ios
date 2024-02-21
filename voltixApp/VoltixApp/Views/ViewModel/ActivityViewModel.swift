//
//  ActivityViewModel.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 14/02/2024.
//

import Foundation
import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

public class ActivityViewModel : ObservableObject{
    public static func generateHighQualityQRCode(from string: String, withScale scale: CGFloat = 3.0) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        
        guard let qrImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: scale, y: scale) // Scale the QR code
        let scaledQRImage = qrImage.transformed(by: transform)
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledQRImage, from: scaledQRImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}
