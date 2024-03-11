import Foundation

class SolanaRPCResponse<T: Decodable>: Decodable {
	let jsonrpc: String
	let result: T
	let id: Int
}

class SolanaBalanceResponse: Decodable {
	let context: SolanaContext
	let value: Int
}

class SolanaContext: Decodable {
	let slot: Int
}
