//
//  FileExporterSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/08/2025.
//

import Foundation
import SwiftUI

struct FileExporterModel {
    let url: URL
    let name: String
    let fileTransform: (URL) -> FileDocument?
}

extension View {
    func fileExporter(isPresented: Binding<Bool>, fileModel: Binding<FileExporterModel?>, completion: @escaping (Result<Bool, Error>) -> Void) -> some View {
        modifier(FileExporterSheet(isPresented: isPresented, fileModel: fileModel, completion: completion))
    }
}

struct FileExporterSheet: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var fileModel: FileExporterModel?
    var completion: (Result<Bool, Error>) -> Void
    
    func body(content: Content) -> some View {
        fileExporter(content: content)
    }
}

#if os(iOS)
extension FileExporterSheet {
    func fileExporter(content: Content) -> some View {
        content
            .unwrap(fileModel) { view, fileModel in
                view.shareSheet(isPresented: $isPresented, activityItems: [fileModel.url])  { didSave in
                    completion(.success(didSave))
                }
            }
    }
}
#elseif os(macOS)
extension FileExporterSheet {
    func fileExporter(content: Content) -> some View {
        content
            .unwrap(fileModel) { view, fileModel in
                view.fileExporter(
                    isPresented: $isPresented,
                    document: fileModel.fileTransform(fileModel.url),
                    contentType: .data,
                    defaultFilename: fileModel.name
                ) { result in
                    switch result {
                    case .success:
                        completion(.success(true))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
    }
}
#endif
