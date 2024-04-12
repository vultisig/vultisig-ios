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
}
