//
//  ImageFileDocument+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-27.
//

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct ImageFileDocument: FileDocument {
    var image: UIImage

    @MainActor
    init(image: Image) {
        let renderer = ImageRenderer(content: image)

        // Set the scale to match the device's screen scale for better quality
        renderer.scale = 3

        // Render the image to a UIImage
        if let uiImage = renderer.uiImage {
            self.image = uiImage
        } else {
            // Fallback to an empty image if rendering fails
            self.image = UIImage()
        }
    }

    // FileDocument required methods
    static var readableContentTypes: [UTType] { [.png] }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let image = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.image = image
    }
    // swiftlint:disable:next unused_parameter
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let pngData = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: pngData)
    }
}
#endif
