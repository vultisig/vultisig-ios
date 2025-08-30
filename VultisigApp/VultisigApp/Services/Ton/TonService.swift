import Foundation
import WalletCore
import BigInt

struct JettonWalletsResponse: Codable {
    let jetton_wallets: [JettonWalletInfo]
}

struct JettonWalletInfo: Codable {
    let address: String
    let balance: String
    let owner: String  // Raw address string, not a dictionary
    let jetton: String // Raw address string, not a dictionary
    let last_transaction_lt: String?
    let code_hash: String?
    let data_hash: String?
}

struct RunGetMethodResponse: Codable {
    let ok: Bool
    let result: RunGetMethodResult?
    let error: String?
}

struct RunGetMethodResult: Codable {
    let stack: [StackItem]?
    let gas_used: Int64?
    let exit_code: Int?
}

struct StackItem: Codable {
    let type: String?
    let value: StackValue?
    let boc: String?
    
    private enum CodingKeys: String, CodingKey {
        case type, value, boc
    }
}

struct StackValue: Codable {
    let bytes: String?
    let b64: String?
    let boc: String?
    
    private enum CodingKeys: String, CodingKey {
        case bytes, b64, boc
    }
}

struct ApiResponse<T: Codable>: Codable {
    let ok: Bool
    let result: T?
    let error: String?
    let code: Int?
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
    
    func getTONBalance(_ coin: Coin) async throws -> String {
        
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
    
    func getBalance(_ coin: Coin) async throws -> String {
        if coin.isNativeToken {
            return try await getTONBalance(coin)
        } else {
            return try await getJettonBalance(coin)
        }
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
    
    
    func getJettonBalance(_ coin: Coin) async throws -> String {
        // Use Vultisig proxy jetton wallets endpoint (matches Android)
        guard let url = URL(string: Endpoint.fetchTonJettonBalance(address: coin.address, jettonAddress: coin.contractAddress)) else {
            throw URLError(.badURL)
        }
        
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[TON] getJettonBalance non-200: \(httpResponse.statusCode) url=\(url) body=\(body)")
            return String.zero
        }
        
        // Parse using proper Codable struct
        do {
            let jettonResponse = try JSONDecoder().decode(JettonWalletsResponse.self, from: data)
            
            // Find matching jetton wallet by contract address
            let normalizedCoinAddress = TONAddressConverter.toUserFriendly(address: coin.contractAddress, bounceable: true, testnet: false) ?? coin.contractAddress
            
            for wallet in jettonResponse.jetton_wallets {
                let normalizedJettonAddress = TONAddressConverter.toUserFriendly(address: wallet.jetton, bounceable: true, testnet: false) ?? wallet.jetton
                
                if normalizedJettonAddress == normalizedCoinAddress {
                    return wallet.balance
                }
            }
        } catch {
            print("❌ Failed to parse jetton balance response: \(error)")
        }
        
        return String.zero
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
    
    func getJettonWalletAddressAsync(ownerAddress: String, masterAddress: String) async -> String? {
        return await runGetWalletAddress(owner: ownerAddress, master: masterAddress)
    }
    
    // Too complex to use a struct.
    private func runGetWalletAddress(owner: String, master: String) async -> String? {
        guard let boc = TONAddressConverter.toBoc(address: owner) else { return nil }
        let payload: [String: Any] = [
            "address": master,
            "method": "get_wallet_address",
            "stack": [["tvm.Slice", boc]]
        ]
        guard let url = URL(string: Endpoint.tonApiRunGetMethod()) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            
            // Try to parse with proper Codable struct first
            if let response = try? JSONDecoder().decode(RunGetMethodResponse.self, from: data),
               response.ok == true,
               let result = response.result {
                // Handle structured response
                return parseJettonWalletFromStack(result.stack)
            }
            
            // Fallback to manual JSON parsing for compatibility
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok,
               let result = json["result"] as? [String: Any],
               let stackAny = result["stack"] {
                if let stack = stackAny as? [[Any]] {
                    for entry in stack where entry.count >= 2 {
                        let value = entry[1]
                        var blob: String?
                        if let s = value as? String { blob = s }
                        else if let dict = value as? [String: Any] { blob = (dict["bytes"] as? String) ?? (dict["b64"] as? String) ?? (dict["boc"] as? String) }
                        if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                            return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                        }
                    }
                } else if let stack = stackAny as? [[String: Any]] {
                    for item in stack {
                        if let cell = item["value"] as? [String: Any] {
                            let blob = (cell["bytes"] as? String) ?? (cell["b64"] as? String) ?? (cell["boc"] as? String)
                            if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                                return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                            }
                        } else if let blob = item["boc"] as? String, let addr = TONAddressConverter.fromBoc(boc: blob) {
                            return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                        }
                    }
                }
            }
        } catch { }
        return nil
    }
    
    private func parseJettonWalletFromStack(_ stack: [StackItem]?) -> String? {
        guard let stack = stack else { return nil }
        
        for item in stack {
            // Try direct boc field first
            if let boc = item.boc, let addr = TONAddressConverter.fromBoc(boc: boc) {
                return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
            }
            
            // Try value field
            if let value = item.value {
                let blob = value.bytes ?? value.b64 ?? value.boc
                if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                    return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                }
            }
        }
        return nil
    }
    
}
