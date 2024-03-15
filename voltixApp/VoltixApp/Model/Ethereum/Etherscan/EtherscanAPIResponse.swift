//
//  EtherscanAPIResponse.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class EtherscanAPIResponse: Codable {
    let status: String
    let message: String
    let result: [EtherscanAPITransactionDetail]?
}
