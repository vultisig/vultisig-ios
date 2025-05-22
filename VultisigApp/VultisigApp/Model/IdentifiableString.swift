//
//  IdentifiableString.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 21/05/25.
//

import Foundation

struct IdentifiableString: Identifiable, Equatable {
    let id = UUID()
    let value: String
}
