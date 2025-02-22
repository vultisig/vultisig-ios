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
}
