//
//  ImportWalletType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/12/2025.
//

import Foundation

enum ImportWalletType: Int, CaseIterable, FilledSegmentedControlType {
    case vault
    case seedphrase
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .vault:
            "importShare".localized
        case .seedphrase:
            "importSeedphrase".localized.lowercased().capitalized
        }
    }
}
