//
//  FileExporterSheet.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 28/08/2025.
//

import Foundation
import SwiftUI

struct FileExporterModel<D: FileDocument> {
    let url: URL
    let name: String
    let file: D
}

extension View {
    func fileExporter<D: FileDocument>(isPresented: Binding<Bool>, fileModel: Binding<FileExporterModel<D>?>, completion: @escaping (Result<Bool, Error>) -> Void) -> some View {
        modifier(FileExporterSheet(isPresented: isPresented, fileModel: fileModel, completion: completion))
    }
}

struct FileExporterSheet<D: FileDocument>: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var fileModel: FileExporterModel<D>?
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
                view.shareSheet(isPresented: $isPresented, activityItems: [fileModel.url]) { didSave in
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
                    document: fileModel.file,
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
