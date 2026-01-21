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
    let resetData: () -> Void
    let handleFileImport: (_ result: Result<[URL], Error>) -> Void

#if os(iOS)
    let selectedImage: UIImage?
#elseif os(macOS)
    let selectedImage: NSImage?
#endif

    @State var showFileImporter = false
    @State var isUploading: Bool = false

    var body: some View {
        container
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
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .background(Theme.colors.bgButtonPrimary.opacity(0.15))
        .cornerRadius(10)
        .overlay(
            ZStack {
                getOverlay(isUploading ? 2 : 1)
                getOverlay(1)
                    .padding(isUploading ? 8 : 0)
            }
        )
        .animation(.easeInOut, value: isUploading)
    }

    var placeholderImage: some View {
        VStack(spacing: 12) {
            icon
            title
        }
    }

    var icon: some View {
        Image(systemName: "desktopcomputer.and.arrow.down")
            .font(Theme.fonts.display)
            .foregroundColor(Theme.colors.bgButtonPrimary)
    }

    var title: some View {
        Text(NSLocalizedString(isUploading ? "dropFileHere" : "uploadQRCodeImage", comment: "Upload backup file"))
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .animation(.none, value: isUploading)
    }

    private func handleTap() {
        showFileImporter = true
    }

    func fileCell(_ name: String) -> some View {
        ImportFileCell(name: name, resetData: resetData)
    }

    private func getOverlay(_ lineWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.colors.bgButtonPrimary, style: StrokeStyle(lineWidth: lineWidth, dash: [10]))
    }
}

#Preview {
    func reset() {
        print("RESET")
    }

    func handleFileImport(result: Result<[URL], Error>) {
        print("IMPORTED")
    }

    return FileQRCodeImporterMac(fileName: "File", resetData: reset, handleFileImport: handleFileImport, selectedImage: nil)
        .padding(100)
}
