import Foundation

extension SolanaService {
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
