//
//  ImageFileDocument.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-29.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
struct ImageFileDocument: FileDocument {
    var image: UIImage

    @MainActor
    init(image: Image) {
        // Convert the SwiftUI Image to a UIImage
        let renderer = ImageRenderer(content: image)
        let size = CGSize(width: 960, height: 1380)  // Adjust the size according to your needs

        let uiImage = renderer.uiImage?.resized(to: size) ?? UIImage()
        self.image = uiImage
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

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let pngData = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: pngData)
    }
}
#elseif os(macOS)
struct ImageFileDocument: FileDocument {
    var image: NSImage
    
    @MainActor
    init(image: Image) {
        // Convert the SwiftUI Image to an NSImage without using 'self'
        let renderer = ImageRenderer(content: image)
        let size = NSSize(width: 960, height: 1380)  // Adjust the size according to your needs

        let nsImage = NSImage(size: size)
        
        nsImage.lockFocus()
        
        if let cgImage = renderer.cgImage {
            let context = NSGraphicsContext.current?.cgContext
            context?.draw(cgImage, in: NSRect(origin: .zero, size: size))
        }
        
        nsImage.unlockFocus()
        self.image = nsImage
    }

    // FileDocument required methods
    static var readableContentTypes: [UTType] { [.png] }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let image = NSImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.image = image
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: pngData)
    }
}
#endif
