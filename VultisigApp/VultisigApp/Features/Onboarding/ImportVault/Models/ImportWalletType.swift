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
            "Import share"
        case .seedphrase:
            "Import seedphrase"
        }
    }
}
