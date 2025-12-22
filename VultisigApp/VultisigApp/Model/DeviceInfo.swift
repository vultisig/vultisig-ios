//
//  File.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//

import Foundation
import SwiftUI

struct DeviceInfo: Hashable {
    var Index: Int
    var Signer: String

    init(Index: Int, Signer: String) {
        self.Index = Index
        self.Signer = Signer
    }
}
