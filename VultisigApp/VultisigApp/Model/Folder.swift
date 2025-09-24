//
//  Folder.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-04.
//

import Foundation
import SwiftData

@Model
class Folder: Hashable, Equatable {
    var id = UUID()
    var folderName: String
    var containedVaultNames: [String]
    var order: Int
    
    init(folderName: String, containedVaultNames: [String], order: Int) {
        self.folderName = folderName
        self.containedVaultNames = containedVaultNames
        self.order = order
    }
    
    static func == (lhs: Folder, rhs: Folder) -> Bool {
        lhs.folderName == rhs.folderName && lhs.containedVaultNames == rhs.containedVaultNames
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(folderName)
        hasher.combine(containedVaultNames)
    }
    
    static let example = Folder(folderName: "Folder", containedVaultNames: ["12345"], order: 0)
}
