import Foundation

extension SolanaService {
    class SolanaRPCResponse<T: Decodable>: Decodable {
        let result: T
    }

    class SolanaBalanceResponse: Decodable {
        let context: SolanaContext
        let value: Int
    }

    class SolanaContext: Decodable {
        let slot: Int
    }

    class SolanaDetailedRPCResult<T: Decodable>: Decodable {
        let result: SolanaDetailedResult<T>
    }

    class SolanaDetailedResult<T: Decodable>: Decodable {
        let context: SolanaDetailedContext
        let value: T
    }

    class SolanaDetailedContext: Decodable {
        let apiVersion: String
        let slot: Int
    }
}
