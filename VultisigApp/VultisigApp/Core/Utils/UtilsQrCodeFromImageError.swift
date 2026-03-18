//
//  UtilsQrCodeFromImageError.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI

protocol ErrorWithCustomPresentation: Error {
    var errorTitle: String { get }
    var errorDescription: String { get }
}

enum UtilsQrCodeFromImageError: Error, LocalizedError, ErrorWithCustomPresentation {
    case URLInaccessible
    case NoQRCodesDetected
    case FailedToLoadImage
    case VaultNotImported(publicKey: String)

    var errorTitle: String {
        switch self {
        case .URLInaccessible, .NoQRCodesDetected, .FailedToLoadImage:
            return NSLocalizedString("error", comment: "")
        case .VaultNotImported:
            return NSLocalizedString("vaultNotImportedTitle", comment: "")
        }
    }

    var errorDescription: String {
        switch self {
        case .URLInaccessible:
            return "Failed to access URL"
        case .NoQRCodesDetected:
            return "No QR codes detected"
        case .FailedToLoadImage:
            return "Failed to load image from URL"
        case .VaultNotImported:
            return NSLocalizedString("vaultNotImportedDescription", comment: "")
        }
    }
}
