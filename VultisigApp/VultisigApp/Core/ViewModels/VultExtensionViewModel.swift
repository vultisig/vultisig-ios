//
//  VultExtensionViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-21.
//

import SwiftUI

class VultExtensionViewModel: ObservableObject {
    @Published var documentData: FileDocumentConfiguration<VULTFileDocument>? = nil
    @Published var documentUrl: URL? = nil
    @Published var showImportView: Bool = false

    /// Raised when a document scene hands a file over, and lowered by whoever
    /// acts on it.
    ///
    /// A flag rather than "is `documentData` still set?", because this view model
    /// is shared by every scene the app can open — a `WindowGroup` and a
    /// `DocumentGroup` — and the document stays set until the import screen
    /// reads it. Two screens both seeing it there is two pushes of the same
    /// import route for one file.
    @Published private(set) var isDocumentImportPending: Bool = false

    func handOff(documentData: FileDocumentConfiguration<VULTFileDocument>) {
        self.documentData = documentData
        isDocumentImportPending = true
    }

    /// - Returns: whether the caller is the one that should open the import,
    ///   which is true for exactly one caller per document.
    func consumeDocumentImport() -> Bool {
        guard isDocumentImportPending else { return false }
        isDocumentImportPending = false
        return true
    }
}
