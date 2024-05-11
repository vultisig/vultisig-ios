//
//  CameraView.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/05/24.
//
import SwiftUI
import Combine

struct CameraView: View {
    @StateObject private var camera = Camera()  // Use StateObject since Camera is an ObservableObject
    private let context = CIContext(options: nil)  // Create a single CIContext for reuse

    var body: some View {
        ZStack {
            if let image = camera.image {
                Image(uiImage: convertCIImageToUIImage(ciImage: image))
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black  // Show a black screen when no image is available
            }
        }
        .onAppear {
            camera.setUpAndStartCamera()
        }
    }

    func convertCIImageToUIImage(ciImage: CIImage) -> UIImage {
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImage)
        } else {
            return UIImage(systemName: "exclamationmark.triangle") ?? UIImage()
        }
    }
}
