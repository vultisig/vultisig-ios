import Foundation

	// MARK: - SolanaService Extension for Recent Block Hash
extension SolanaService {
	
	
	
	
	
	struct SolanaRecentBlockhashResponse: Codable {
		let context: SolanaRecentBlockhashContext
		let value: SolanaRecentBlockhashValue
	}
	
	struct SolanaRecentBlockhashContext: Codable {
		let slot: Int
	}
	
	struct SolanaRecentBlockhashValue: Codable {
		let blockhash: String
		let feeCalculator: SolanaRecentBlockhashFeeCalculator
	}
	
	struct SolanaRecentBlockhashFeeCalculator: Codable {
		let lamportsPerSignature: Int
	}
}
