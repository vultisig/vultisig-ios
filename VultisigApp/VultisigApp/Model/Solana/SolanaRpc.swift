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
    
    class SolanaRPCResponse2<T: Decodable>: Decodable {
        let result: SolanaResult2<T>
    }
    
    class SolanaResult2<T: Decodable>: Decodable {
        let context: SolanaContext2
        let value: T
    }
    
    class SolanaContext2: Decodable {
        let apiVersion: String
        let slot: Int
    }
}
