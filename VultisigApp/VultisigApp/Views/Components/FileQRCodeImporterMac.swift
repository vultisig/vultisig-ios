//
//  FileQRCodeImporterMac.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI
import UniformTypeIdentifiers

struct FileQRCodeImporterMac: View {
    @State var showFileImporter = false
    
    var body: some View {
        button
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(Color.turquoise600.opacity(0.15))
            .cornerRadius(10)
            .overlay (
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 1, dash: [10]))
            )
    }
    
    var button: some View {
        Button {
            handleTap()
        } label: {
            content
        }
    }
    
    var content: some View {
        VStack(spacing: 12) {
            icon
            title
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            print(result)
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
}

#Preview {
    FileQRCodeImporterMac()
        .padding(100)
}
