//
//  TransactionDetail.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class EtherscanAPITransactionDetail: Codable, ObservableObject {
    let blockNumber: String?
    let timeStamp: String?
    let hash: String?
    let nonce: String?
    let blockHash: String?
    let transactionIndex: String?
    let from: String
    let to: String
    let value: String
    let gas: String
    let gasPrice: String
    let isError: String?
    let txreceipt_status: String?
    let input: String?
    let contractAddress: String?
    let cumulativeGasUsed: String?
    let gasUsed: String?
    let confirmations: String?
    
    // Fields that might not exist in all responses, now optional
    let methodId: String?
    let functionName: String?
    
    // Added properties for ERC20, already optional
    let tokenName: String?
    let tokenSymbol: String?
    let tokenDecimal: String?
}
