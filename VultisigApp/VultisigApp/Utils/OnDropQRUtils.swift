//
//  OnDropQRUtils.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-28.
//

import AppKit

class OnDropQRUtils {
    public static func handleOnDrop(providers: [NSItemProvider], handleImageQrCode: @escaping (Data) -> ()) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.image") }) else {
            print("Invalid file type. Please drop an image.")
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
            guard let data = data, let image = NSImage(data: data) else {
                print(error?.localizedDescription ?? "Failed to load image.")
                return
            }

            // Extract QR code data from the image
            if let qrData = extractQRCode(from: image) {
                DispatchQueue.main.async {
                    handleImageQrCode(qrData)
                }
            } else {
                print("No QR code detected in the image.")
            }
        }

        return true
    }

    private static func extractQRCode(from nsImage: NSImage) -> Data? {
        guard let tiffData = nsImage.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

        if let features = detector?.features(in: ciImage), !features.isEmpty {
            for feature in features {
                if let qrFeature = feature as? CIQRCodeFeature, let qrString = qrFeature.messageString {
                    return Data(qrString.utf8)
                }
            }
        }

        return nil
    }
}
