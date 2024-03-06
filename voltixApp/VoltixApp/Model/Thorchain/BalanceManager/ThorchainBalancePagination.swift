//
//  ThorchainBalancePagination.swift
//  VoltixApp
//
//  Created by Enrique Souza Soares on 06/03/2024.
//

import Foundation

class ThorchainBalancePagination: Codable {
    var next_key: String?
    var total: String
    
    init(next_key: String?, total: String) {
        self.next_key = next_key
        self.total = total
    }
}
