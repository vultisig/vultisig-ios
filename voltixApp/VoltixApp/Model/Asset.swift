	//
	//  Asset.swift
	//  VoltixApp
	//
	//  Created by Amol Kumar on 2024-03-04.
	//

import Foundation

class Asset : Codable, Hashable {
	let ticker: String
	let chainName: String
	let image: String
	let priceProviderId: String?
	let chainType: ChainType
	let tokenInfo: Token?
	
	init(ticker: String, chainName: String, image: String, chainType: ChainType, priceProviderId: String?, tokenInfo: Token?) {
		self.ticker = ticker
		self.chainName = chainName
		self.image = image
		self.chainType = chainType
		self.priceProviderId = priceProviderId
		self.tokenInfo = tokenInfo
	}
	
	static func == (lhs: Asset, rhs: Asset) -> Bool {
		lhs.ticker == rhs.ticker 
		&& lhs.chainName == rhs.chainName
		&& lhs.image == rhs.image
		&& lhs.priceProviderId == rhs.priceProviderId
		&& lhs.chainType == rhs.chainType
		&& lhs.tokenInfo == rhs.tokenInfo
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(ticker)
		hasher.combine(chainName)
		hasher.combine(image)
		hasher.combine(priceProviderId)
		hasher.combine(chainType)
		hasher.combine(tokenInfo)
	}
	
	static let example = Asset(ticker: "BTC", chainName: "Bitcoin", image: "BitcoinLogo", chainType: 	.UTXO, priceProviderId: nil, tokenInfo: nil)
}
