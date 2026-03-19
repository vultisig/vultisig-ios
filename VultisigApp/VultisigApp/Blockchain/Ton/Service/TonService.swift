import Foundation
import WalletCore
import BigInt

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
        let (data, response) = try await URLSession.shared.data(for: request)
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

    func getTONBalance(address: String) async throws -> String {

        guard let url = URL(string: Endpoint.fetchTonBalance(address: address)) else {
            throw URLError(.badURL)
        }
        let request = URLRequest(url: url)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let balance = Utils.extractResultFromJson(fromData: data, path: "balance") as? String {
            return balance
        }

        return .zero
    }

    func getBalance(coin: CoinMeta, address: String) async throws -> String {
        if coin.isNativeToken {
            return try await getTONBalance(address: address)
        } else {
            return try await getJettonBalance(coin: coin, address: address)
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

    func getJettonBalance(coin: CoinMeta, address: String) async throws -> String {
        // Use Vultisig proxy jetton wallets endpoint (matches Android)
        guard let url = URL(string: Endpoint.fetchTonJettonBalance(address: address, jettonAddress: coin.contractAddress)) else {
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

            // First attempt: strict model
            if let response = try? JSONDecoder().decode(RunGetMethodResponse.self, from: data),
               response.ok == true,
               let result = response.result {
                if let parsed = parseJettonWalletFromStack(result.stack) { return parsed }
            }

            // Fallback: flexible model that matches array- or object-shaped stack entries
            if let flex = try? JSONDecoder().decode(RunGetMethodFlexibleResponse.self, from: data),
               flex.ok == nil || flex.ok == true,
               let stack = flex.result?.stack {
                for entry in stack {
                    switch entry {
                    case .object(let item):
                        if let boc = item.boc, let addr = TONAddressConverter.fromBoc(boc: boc) {
                            return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                        }
                        if let value = item.value {
                            let blob = value.bytes ?? value.b64 ?? value.boc
                            if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                                return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                            }
                        }
                    case .array(let arr):
                        if let v = arr.value {
                            let blob = v.bytes ?? v.b64 ?? v.boc
                            if let blob, let addr = TONAddressConverter.fromBoc(boc: blob) {
                                return TONAddressConverter.toUserFriendly(address: addr, bounceable: true, testnet: false) ?? addr
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error running Ton API: \(error.localizedDescription)")
        }
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
