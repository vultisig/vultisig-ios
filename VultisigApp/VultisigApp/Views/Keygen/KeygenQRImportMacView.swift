//
//  KeygenQRImportMacView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-27.
//

import SwiftUI

struct KeygenQRImportMacView: View {
    @State var fileName: String? = nil
    @State private var selectedImage: NSImage?
    @State var isButtonEnabled = false
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .navigationTitle("pair")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackButton()
            }
        }
    }
    
    var content: some View {
        VStack(spacing: 32) {
            title
            uploadSection
            Spacer()
            button
        }
        .padding(40)
    }
    
    var title: some View {
        Text(NSLocalizedString("uploadQRCodeImageKeygen", comment: ""))
            .font(.body16MontserratBold)
            .foregroundColor(.neutral0)
    }
    
    var uploadSection: some View {
        FileQRCodeImporterMac(
            fileName: fileName, 
            selectedImage: selectedImage,
            resetData: resetData,
            handleFileImport: handleFileImport
        )
    }
    
    var button: some View {
        FilledButton(title: "continue")
            .disabled(!isButtonEnabled)
            .grayscale(isButtonEnabled ? 0 : 1)
    }
    
    private func resetData() {
        fileName = nil
        selectedImage = nil
        isButtonEnabled = false
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            setValues(urls)
        case .failure(let error):
            print("Error importing file: \(error.localizedDescription)")
        }
    }
    
    private func setValues(_ urls: [URL]) {
        do {
            if let url = urls.first {
                let _ = url.startAccessingSecurityScopedResource()
                fileName = url.lastPathComponent
                
                let imageData = try Data(contentsOf: url)
                if let nsImage = NSImage(data: imageData) {
                    selectedImage = nsImage
                }
                isButtonEnabled = true
            }
        } catch {
            print(error)
        }
    }
}

#Preview {
    KeygenQRImportMacView()
}
