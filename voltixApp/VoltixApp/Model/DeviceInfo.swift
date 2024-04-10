//
//  File.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 10/04/2024.
//

import Foundation
import SwiftUI

struct DeviceInfo {
    var Index: Int
    var Signer: String
    var PubKey: String
    
    init(Index: Int, Signer: String, PubKey: String) {
        self.Index = Index
        self.Signer = Signer
        self.PubKey = PubKey
    }
}
