import Foundation
import SwiftData
import BigInt

class Coin: Codable, Hashable {
	let chain: Chain
	let ticker: String
	let logo: String
	let address: String
	let chainType: ChainType
	
	@DecodableDefault.EmptyString var decimals: String
	@DecodableDefault.EmptyString var hexPublicKey: String
	@DecodableDefault.EmptyString var feeUnit: String
	@DecodableDefault.EmptyString var priceProviderId: String
	@DecodableDefault.EmptyString var contractAddress: String
	@DecodableDefault.EmptyString var rawBalance: String
	@DecodableDefault.False var isNativeToken: Bool
	@DecodableDefaultDouble var priceRate: Double
	
	init(chain: Chain, ticker: String, logo: String, address: String, priceRate: Double, chainType: ChainType, decimals: String, hexPublicKey: String, feeUnit: String, priceProviderId: String, contractAddress: String, rawBalance: String, isNativeToken: Bool) {
		self.chain = chain
		self.ticker = ticker
		self.logo = logo
		self.address = address
		self.priceRate = priceRate
		self.chainType = chainType
		self.decimals = decimals
		self.hexPublicKey = hexPublicKey
		self.feeUnit = feeUnit
		self.priceProviderId = priceProviderId
		self.contractAddress = contractAddress
		self.rawBalance = rawBalance
		self.isNativeToken = isNativeToken
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(ticker)
		hasher.combine(address)
	}
	
	static func == (lhs: Coin, rhs: Coin) -> Bool {
		return lhs.ticker == rhs.ticker && lhs.address == rhs.address
	}
	
	var balance: BigInt? {
		BigInt(rawBalance, radix: 10)
	}
	
	var balanceDecimal: Double {
		let tokenBalance = Double(rawBalance) ?? 0.0
		let tokenDecimals = Double(Int(decimals) ?? 0)
		return tokenBalance / pow(10, tokenDecimals)
	}
	
	var balanceString: String {
		String(format: "%.\(Int(decimals) ?? 0)f", balanceDecimal)
	}
	
	func getAmountInUsd(_ amount: Double) -> String {
		let balanceInUsd = amount * priceRate
		return String(format: "%.2f", balanceInUsd)
	}
	
	func getAmountInTokens(_ usdAmount: Double) -> String {
		let tokenAmount = usdAmount / priceRate
		return String(format: "%.\(Int(decimals) ?? 0)f", tokenAmount)
	}
	
	var balanceInUsd: String {
		let balanceInUsd = balanceDecimal * priceRate
		return "US$ \(String(format: "%.2f", balanceInUsd))"
	}
	
	static let example = Coin(chain: Chain.Bitcoin, ticker: "BTC", logo: "BitcoinLogo", address: "bc1qxyz...", priceRate: 20000.0, chainType: ChainType.UTXO, decimals: "8", hexPublicKey: "HexPublicKeyExample", feeUnit: "Satoshi", priceProviderId: "Bitcoin", contractAddress: "ContractAddressExample", rawBalance: "500000000", isNativeToken: false)
}
