import Foundation

// Define the structures for responses and interfaces
struct TonAddressInformation: Codable {
    var balance: String
    var code: String
    var data: String
    var frozen_hash: String
    var last_transaction_hash: String
    var last_transaction_lt: String
    var status: String
}

struct ApiResponse<T: Codable>: Codable {
    let ok: Bool
    let result: T?
    let error: String?
    let code: Int?
}

struct ResultData: Codable {
    struct AddressInfo: Codable {
        let type = "accountAddress"
        let account_address: String
        enum CodingKeys: CodingKey {
            case account_address
        }
    }

    struct LastTransactionIdInfo: Codable {
        let type = "internal.transactionId"
        let lt: String
        let hash: String
        enum CodingKeys: CodingKey {
            case lt
            case hash
        }
    }

    struct BlockIdInfo: Codable {
        let type = "ton.blockIdExt"
        let workchain: Int
        let shard: String
        let seqno: Int
        let root_hash: String
        let file_hash: String
        enum CodingKeys: CodingKey {
            case workchain
            case shard
            case seqno
            case root_hash
            case file_hash
        }
    }

    struct AccountStateInfo: Codable {
        let type = "wallet.v4.accountState"
        let wallet_id: String
        let seqno: Int
        enum CodingKeys: CodingKey {
            case wallet_id
            case seqno
        }
    }

    var type = "fullAccountState"
    var address: AddressInfo
    var balance: String
    var last_transaction_id: LastTransactionIdInfo
    var block_id: BlockIdInfo
    var sync_utime: Int
    var account_state: AccountStateInfo
    var revision: Int
    let extra: String
}

struct TonBroadcastSuccessResponse: Codable {
    let hash: String
}

class TonService {
    
    static let shared = TonService()

    func broadcastTransaction(_ obj: String) async throws -> String {
                
        let body: [String: Any] = ["boc": obj]
        let dataPayload = try JSONSerialization.data(withJSONObject: body, options: [])
        guard let url = URL(string: Endpoint.broadcastTonTransaction()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = dataPayload
        let (data,response) = try await URLSession.shared.data(for: request)
        print("Ton broadcast response: \(String(data: data, encoding: .utf8) ?? "")")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            let result = try JSONDecoder().decode(ApiResponse<TonBroadcastSuccessResponse>.self, from: data)
            return result.result?.hash ?? ""
        case 500:
            let result = try JSONDecoder().decode(ApiResponse<String>.self, from: data)
            let duplicate = result.error?.contains("duplicate message") ?? false
            if duplicate {
                return ""
            } else {
                throw NSError(domain: "Server Error", code: 500, userInfo: [NSLocalizedDescriptionKey: result.error ?? "Unknown server error"])
            }
        default:
            throw NSError(domain: "Unexpected response code", code: httpResponse.statusCode, userInfo: nil)
        }
    }

    func getBalance(_ coin: Coin) async throws -> String {
        
        guard let url = URL(string: Endpoint.fetchTonBalance(address: coin.address)) else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let balance = Utils.extractResultFromJson(fromData: data, path: "balance") as? String {
            return balance
        }
                
        return .zero
    }

    func getSpecificTransactionInfo(_ coin: Coin) async throws -> (UInt64, UInt64) {
        
        let now = Date()
        let futureDate = now.addingTimeInterval(600)
        let expireAt = UInt64(futureDate.timeIntervalSince1970)
        
        
        guard let url = URL(string: Endpoint.fetchExtendedAddressInformation(address: coin.address)) else {
            throw URLError(.badURL)
        }
        
        let request = URLRequest(url: url)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        var seqno = UInt64(0)
        if let rseqno = Utils.extractResultFromJson(fromData: data, path: "result.account_state.seqno") as? UInt64 {
            seqno = rseqno
        } else if let rseqnoString = Utils.extractResultFromJson(fromData: data, path: "result.account_state.seqno") as? String {
            seqno = UInt64(rseqnoString) ?? 0
        }
        
        return (seqno, expireAt)
    }
    
    func getWalletState(_ address: String) async throws -> String {
        guard let url = URL(string: Endpoint.fetchTonBalance(address: address)) else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let status = Utils.extractResultFromJson(fromData: data, path: "status") as? String {
            return status
        }
        
        return "uninit" // Default to uninitialized if status not found
    }

}
