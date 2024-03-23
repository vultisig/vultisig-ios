//
//  Price.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-04.
//

import Foundation

class ETHInfoPrice: Codable {
	let rate: Double
	let diff: Double
	let diff7d: Double
	let ts: Int
	let marketCapUsd: Double
	let availableSupply: Double
	let volume24h: Double
	
	init(){
		self.rate = 0.0
		self.diff = 0.0
		self.diff7d = 0.0
		self.ts = 0
		self.marketCapUsd = 0.0
		self.availableSupply = 0.0
		self.volume24h = 0.0
	}
}
