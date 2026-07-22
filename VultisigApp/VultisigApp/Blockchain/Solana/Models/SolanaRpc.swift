import Foundation

extension SolanaService {
    class SolanaDetailedRPCResult<T: Decodable>: Decodable {
        let result: SolanaDetailedResult<T>
    }

    class SolanaDetailedResult<T: Decodable>: Decodable {
        let value: T
    }
}
