//
//  OnDropQRUtils.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

enum OnDropQRError: Error {
    case noItems
    case invalidData
}

class OnDropQRUtils {
    
    public static func handleOnDrop(providers: [NSItemProvider], handleImageQrCode: @escaping (Data) -> Void) -> Bool {
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
    
    public static func handleFileQRCodeImporterMacDrop(providers: [NSItemProvider], completion: @escaping (Result<[URL], Error>) -> Void) {
        var urls = [URL]()
        var dropError: Error? = nil

        let dispatchGroup = DispatchGroup()
        
        for provider in providers {
            dispatchGroup.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                if let error = error {
                    dropError = error
                    dispatchGroup.leave()
                    return
                }
                
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                } else {
                    dropError = OnDropQRError.invalidData
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            if let error = dropError {
                completion(.failure(error))
            } else if urls.isEmpty {
                completion(.failure(OnDropQRError.noItems))
            } else {
                completion(.success(urls))
            }
        }
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
#endif
