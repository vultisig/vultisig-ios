//
//  FileQRCodeImporterMac.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI
import UniformTypeIdentifiers

struct FileQRCodeImporterMac: View {
    let fileName: String?
    let selectedImage: NSImage?
    let resetData: () -> ()
    let handleFileImport: (_ result: Result<[URL], Error>) -> ()
    
    @State var showFileImporter = false
    
    var body: some View {
        VStack {
            button
            
            if let name = fileName {
                fileCell(name)
            }
        }
    }
    
    var button: some View {
        Button {
            handleTap()
        } label: {
            content
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }
    
    var content: some View {
        ZStack {
            if let selectedImage {
                getPreviewImage(selectedImage)
            } else {
                placeholderImage
            }
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .background(Color.turquoise600.opacity(0.15))
        .cornerRadius(10)
        .overlay (
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 1, dash: [10]))
        )
    }
    
    var placeholderImage: some View {
        VStack(spacing: 12) {
            icon
            title
        }
    }
    
    var icon: some View {
        Image(systemName: "desktopcomputer.and.arrow.down")
            .font(.title60MontserratLight)
            .foregroundColor(.turquoise600)
    }
    
    var title: some View {
        Text(NSLocalizedString("uploadQRCodeImage", comment: ""))
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    private func handleTap() {
        showFileImporter = true
    }
    
    private func fileCell(_ name: String) -> some View {
        ImportFileCell(name: name, resetData: resetData)
    }
    
    private func getPreviewImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(.vertical, 18)
    }
}

#Preview {
    func reset() {
        print("RESET")
    }
    
    func handleFileImport(result: Result<[URL], Error>) {
        print("IMPORTED")
    }
    
    return FileQRCodeImporterMac(fileName: "File", selectedImage: nil, resetData: reset, handleFileImport: handleFileImport)
        .padding(100)
}
