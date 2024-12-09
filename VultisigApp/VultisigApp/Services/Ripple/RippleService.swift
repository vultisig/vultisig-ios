//
//  RippleService.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 08/12/24.
//

import Foundation
import SwiftUI
import WalletCore

class RippleService {
    
    static let shared = RippleService()
    
    private let rpcURL2 = URL(string: Endpoint.rippleServiceRpc)!
    
    func broadcastTransaction(_ hex: String) async throws -> String {
        
        print ("Broadcasting transaction...")
        print ("Transaction: \(hex)")
        
        return ""
    }
    
    func getBalance(_ coin: Coin) async throws -> String {
        
        let accoountInfo = try await self.fetchAccountsInfo(for: coin.address)
        
        let balance = accoountInfo?.result?.accountData?.balance
        
        return balance ?? "0"
        
    }
    
    
    func fetchAccountsInfo(for walletAddress: String) async throws
        -> RippleAccountResponse?
    {
        do {
            let requestBody: [String: Any] = [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "account_info",
                "params": [
                    
                    [
                        "account": walletAddress,
                        "ledger_index": "current",
                        "queue": true
                    ],

                ],
            ]

            let data = try await postRequest(with: requestBody, url: rpcURL2)
            
            
            let decoder = JSONDecoder()
            guard let response = try? decoder.decode(RippleAccountResponse.self, from: data) else { return nil }

            return response
        } catch {
            print("Error in fetchTokenAccountsByOwner:")
            throw error
        }
    }
    
    private func postRequest(with body: [String: Any], url: URL) async throws
        -> Data
    {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.httpMethod = "POST"
            request.addValue(
                "application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: body, options: [])

            let (data, response) = try await URLSession.shared.data(
                for: request)

            if let httpResponse = response as? HTTPURLResponse,
                let cacheControl = httpResponse.allHeaderFields["Cache-Control"]
                    as? String,
                cacheControl.contains("max-age") == false
            {

                // Set a default caching duration if none is provided
                let userInfo = ["Cache-Control": "max-age=120"]  // 2 minutes
                let cachedResponse = CachedURLResponse(
                    response: httpResponse, data: data, userInfo: userInfo,
                    storagePolicy: .allowed)
                URLCache.shared.storeCachedResponse(
                    cachedResponse, for: request)
            }

            return data
        } catch {
            print("Error in postRequest:")
            throw error
        }
    }
    
}

struct RippleAccountResponse: Codable {
    let result: Result?
    
    struct Result: Codable {
        let accountData: AccountData?
        let ledgerCurrentIndex: Int?
        let queueData: QueueData?
        let status: String?
        let validated: Bool?
        
        enum CodingKeys: String, CodingKey {
            case accountData = "account_data"
            case ledgerCurrentIndex = "ledger_current_index"
            case queueData = "queue_data"
            case status
            case validated
        }
    }
    
    struct AccountData: Codable {
        let account: String?
        let balance: String?
        let flags: Int?
        let ledgerEntryType: String?
        let ownerCount: Int?
        let previousTxnID: String?
        let previousTxnLgrSeq: Int?
        let sequence: Int?
        let index: String?
        
        enum CodingKeys: String, CodingKey {
            case account = "Account"
            case balance = "Balance"
            case flags = "Flags"
            case ledgerEntryType = "LedgerEntryType"
            case ownerCount = "OwnerCount"
            case previousTxnID = "PreviousTxnID"
            case previousTxnLgrSeq = "PreviousTxnLgrSeq"
            case sequence = "Sequence"
            case index
        }
    }
    
    struct QueueData: Codable {
        let authChangeQueued: Bool?
        let highestSequence: Int?
        let lowestSequence: Int?
        let maxSpendDropsTotal: String?
        let transactions: [Transaction]?
        let txnCount: Int?
        
        enum CodingKeys: String, CodingKey {
            case authChangeQueued = "auth_change_queued"
            case highestSequence = "highest_sequence"
            case lowestSequence = "lowest_sequence"
            case maxSpendDropsTotal = "max_spend_drops_total"
            case transactions
            case txnCount = "txn_count"
        }
    }
    
    struct Transaction: Codable {
        let authChange: Bool?
        let fee: String?
        let feeLevel: String?
        let maxSpendDrops: String?
        let seq: Int?
        let lastLedgerSequence: Int?
        
        enum CodingKeys: String, CodingKey {
            case authChange = "auth_change"
            case fee
            case feeLevel = "fee_level"
            case maxSpendDrops = "max_spend_drops"
            case seq
            case lastLedgerSequence = "LastLedgerSequence"
        }
    }
}
