//
//  UtilsQrCodeFromImageError.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI

enum UtilsQrCodeFromImageError: Error, LocalizedError {
    case URLInaccessible
    case NoQRCodesDetected
    case FailedToLoadImage

    var errorDescription: String? {
        switch self {
        case .URLInaccessible:
            return "Failed to access URL"
        case .NoQRCodesDetected:
            return "No QR codes detected"
        case .FailedToLoadImage:
            return "Failed to load image from URL"
        }
    }
}
