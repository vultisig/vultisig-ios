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
    let contractAddress: String?
	let chainType: ChainType
    
	init(ticker: String, chainName: String, image: String, contractAddress: String?, chainType: ChainType) {
        self.ticker = ticker
        self.chainName = chainName
        self.image = image
        self.contractAddress = contractAddress
		self.chainType = chainType
    }
    
    static func == (lhs: Asset, rhs: Asset) -> Bool {
		lhs.ticker == rhs.ticker && lhs.chainName == rhs.chainName && lhs.image == rhs.image && lhs.contractAddress == rhs.contractAddress && lhs.chainType == rhs.chainType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ticker)
        hasher.combine(chainName)
        hasher.combine(image)
        hasher.combine(contractAddress)
		hasher.combine(chainType)
    }
    
	static let example = Asset(ticker: "BTC", chainName: "Bitcoin", image: "BitcoinLogo", contractAddress: "bc1psrjtwm7682v6nhx2...uwfgcfelrennd7pcvq", chainType: 	.UTXO)
}
