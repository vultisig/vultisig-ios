import Foundation
import BigInt
import WalletCore
import CryptoSwift

// Extend RpcEvmService with ENS resolution methods
extension RpcEvmService {
    private static let ENS_REGISTRY_ADDRESS = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"

    // Function to resolve ENS name to Ethereum address
    func resolveENS(ensName: String) async throws -> String {
        let node = ensName.namehash()

        // Get resolver address from the ENS registry
        let resolverAddress = try await fetchResolver(node: node)

        // Fetch the Ethereum address from the resolver
        return try await fetchAddressFromResolver(node: node, resolverAddress: resolverAddress)
    }

    // Helper method to fetch resolver address for a node
    private func fetchResolver(node: String) async throws -> String {
        let params: [Any] = [
            ["to": RpcEvmService.ENS_REGISTRY_ADDRESS, "data": "0x0178b8bf" + node.stripHexPrefix()],
            "latest"
        ]

        let result = try await strRpcCall(method: "eth_call", params: params)

        // Convert the result to a Data object
        if let data = Data(hexString: result.stripHexPrefix()), data.count == 32 {
            // Extract the last 20 bytes, which represent the resolver address
            let resolverAddressData = data.suffix(20)

            // Convert the resolver address data to a hex string and return
            return "0x" + resolverAddressData.toHexString()
        } else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid resolver address data")
        }
    }

    // Helper method to fetch address from resolver
    private func fetchAddressFromResolver(node: String, resolverAddress: String) async throws -> String {
        let params: [Any] = [
            ["to": resolverAddress, "data": "0x3b3b57de" + node.stripHexPrefix()],
            "latest"
        ]

        let result = try await strRpcCall(method: "eth_call", params: params)

        // Convert the result to a Data object
        if let data = Data(hexString: result.stripHexPrefix()), data.count == 32 {
            // Extract the last 20 bytes, which represent the Ethereum address
            let addressData = data.suffix(20)

            // Convert the address data to a hex string and return
            return "0x" + addressData.toHexString()
        } else {
            throw RpcEvmServiceError.rpcError(code: -1, message: "Invalid address data")
        }
    }
}
