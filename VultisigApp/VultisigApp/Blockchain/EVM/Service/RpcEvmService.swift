import Foundation
import BigInt

enum RpcEvmServiceError: LocalizedError {
    case rpcError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .rpcError(code, message):
            return "RPC Error \(code): \(message)"
        }
    }
}

class RpcEvmService: RpcService {

    func getTokenInfo(contractAddress: String) async throws -> (name: String, symbol: String, decimals: Int) {
        do {
            // Define ABI for ERC20 functions
            let erc20Abi = [
                "0x06fdde03", // name()
                "0x95d89b41", // symbol()
                "0x313ce567"  // decimals()
            ]

            // Fetch token details in parallel
            async let nameHex = fetchERC20Data(methodId: erc20Abi[0], contractAddress: contractAddress)
            async let symbolHex = fetchERC20Data(methodId: erc20Abi[1], contractAddress: contractAddress)
            async let decimalsHex = fetchERC20Data(methodId: erc20Abi[2], contractAddress: contractAddress)

            // Await results
            let nameData = try await nameHex
            let symbolData = try await symbolHex
            let decimalsData = try await decimalsHex

            // Decode hex values to respective types
            let name = try decodeAbiString(from: nameData)
            let symbol = try decodeAbiString(from: symbolData)
            let decimals = Int(hex: decimalsData) ?? 0

            return (name, symbol, decimals)
        } catch {
            return (.empty, .empty, .zero)
        }
    }

    private func fetchERC20Data(methodId: String, contractAddress: String) async throws -> String {
        let params: [Any] = [
            ["to": contractAddress, "data": methodId],
            "latest"
        ]
        return try await strRpcCall(method: "eth_call", params: params)
    }

    private func decodeAbiString(from hex: String) throws -> String {
        let cleanedHex = hex.stripHexPrefix()
        guard let data = Data(hexString: cleanedHex) else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid hex string")
        }

        // ABI-encoded strings are padded to 32-byte words. The actual string length is stored at the beginning.
        guard data.count >= 64 else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid ABI-encoded string")
        }

        let lengthData = data[32..<64]
        let length = Int(BigUInt(lengthData))

        guard length > 0 && data.count >= 64 + length else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid ABI-encoded string length")
        }

        let stringData = data[64..<(64 + length)]
        return String(data: stringData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
    }

}
