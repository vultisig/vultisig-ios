//
//  CoinTypeExtension.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 19/03/2024.
//

import Foundation

extension CoinType {
	static func from(string: String) -> CoinType? {
		let coinName = string.replacingOccurrences(of: "-", with: "")
		for coinType in CoinType.allCases {
			if String(describing: coinType).lowercased() == coinName.lowercased() {
				return coinType
			}
		}
		return nil
	}
}

