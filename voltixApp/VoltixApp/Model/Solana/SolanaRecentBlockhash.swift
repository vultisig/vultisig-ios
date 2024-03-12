import Foundation

extension SolanaService {
	
	class SolanaRecentBlockhashResponse: Codable {
		var context = SolanaRecentBlockhashContext()
		var value = SolanaRecentBlockhashValue()
	}
	
	class SolanaRecentBlockhashContext: Codable {
		var slot: Int = 0 // Default value directly assigned
	}
	
	class SolanaRecentBlockhashValue: Codable {
		var blockhash: String = "" // Default value directly assigned
		var feeCalculator = SolanaRecentBlockhashFeeCalculator()
	}
	
	class SolanaRecentBlockhashFeeCalculator: Codable {
		var lamportsPerSignature: Int = 0 // Default value directly assigned
	}
}
