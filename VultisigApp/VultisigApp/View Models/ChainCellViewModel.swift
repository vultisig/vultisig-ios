//
//  ChainCellViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-11.
//

import Foundation

@MainActor
class ChainCellViewModel: ObservableObject {
    func getGroupCount(_ group: GroupedChain) -> String {
        guard group.coins.count>1 else {
            return "1 " + NSLocalizedString("asset", comment: "")
        }

        return "\(group.coins.count) \(NSLocalizedString("assets", comment: ""))"
    }
}
